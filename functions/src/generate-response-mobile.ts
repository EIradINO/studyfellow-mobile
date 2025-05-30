import {onRequest} from "firebase-functions/v2/https"; // v2のonRequestをインポート
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin"; // firebase-adminをインポート
import {VertexAI, Part, Content} from "@google-cloud/vertexai"; // Vertex AI SDKをインポート

// Firebase Admin SDKの初期化（まだ初期化されていない場合）
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

const PROJECT_ID = "studyfellow-42d35";
const FIREBASE_STORAGE_BUCKET = `${PROJECT_ID}.firebasestorage.app`;

const vertexAI = new VertexAI({project: PROJECT_ID, location: "us-central1"});
const generativeModel = vertexAI.getGenerativeModel({
  model: "gemini-2.0-flash",
});

export const generateResponseMobile = onRequest(
  { 
    region: "asia-northeast1",
  },
  async (request, response) => {
    logger.info("generateResponseMobile function triggered", {structuredData: true});

    // CORSヘッダーの設定
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }

    if (request.method !== "POST") {
      response.status(405).send("Method Not Allowed");
      return;
    }

    try {
      const {room_id: roomId, user_id: requestUserId} = request.body; // リクエストからuser_idも受け取ることを想定

      if (!roomId) {
        logger.error("Room ID is missing");
        response.status(400).send({error: "Room ID is required"});
        return;
      }
      // requestUserId はGCS URI構築に必須ではないが、ログや検証のためにあると良い
      logger.info(`Processing for room_id: ${roomId}, request_user_id: ${requestUserId || "N/A"}`);

      const messagesSnapshot = await db.collection("messages")
        .where("room_id", "==", roomId)
        .orderBy("created_at", "asc")
        .get();

      const history: Content[] = messagesSnapshot.docs.flatMap((doc) => {
        const data = doc.data();
        const role = data.role === "user" || data.role === "model" ? data.role : "user";
        const type = data.type || "text";
        const parts: Part[] = [];

        if (type === "text") {
          if (data.content && typeof data.content === "string" && data.content.trim() !== "") {
            parts.push({text: data.content});
          }
        } else if (type === "image" || type === "file") {
          // テキストパート（もしあれば、かつ空文字列でない場合）
          if (data.content && typeof data.content === "string" && data.content.trim() !== "") {
            parts.push({text: data.content});
          }
          
          // ファイルパート
          const messageUserId = data.user_id; // メッセージ送信者のID
          const fileName = data.file_name;
          const mimeType = data.mime_type;

          if (fileName && typeof fileName === "string" && 
              mimeType && typeof mimeType === "string" &&
              messageUserId && typeof messageUserId === "string") {
            // GCS URI を構築: gs://<bucket_name>/chat_attachments/<user_id>/<room_id>/<file_name>
            // バケット名を正しく含めるように修正
            const gcsUri = `gs://${FIREBASE_STORAGE_BUCKET}/chat_attachments/${messageUserId}/${roomId}/${fileName}`;
            parts.push({fileData: {fileUri: gcsUri, mimeType: mimeType}});
            logger.info(`Constructed GCS URI: ${gcsUri} for message ${doc.id}`);
          } else {
            logger.warn(`Missing fileName, mimeType, or userId for ${type} message: ${doc.id}`, {fileName, mimeType, messageUserId});
            return []; 
          }
        } else if (type === "context") {
          // contextメッセージ処理
          const documentId = data.document_id;
          const startPage = data.start_page;
          const endPage = data.end_page;
          const content = data.content && typeof data.content === "string" ? data.content : "";
          if (!documentId || typeof startPage !== "number" || typeof endPage !== "number") {
            logger.warn(`context message missing document_id/start_page/end_page: ${doc.id}`);
            return [];
          }
          // document_metadata取得
          parts.push(...[]); // placeholder for async
          // async対応のため、後で下で置き換え
          return [{role, parts, _contextInfo: {documentId, startPage, endPage, content}}];
        }

        if (parts.length === 0) {
          logger.warn(`Message ${doc.id} (type: ${type}) has no valid parts, skipping.`);
          return [];
        }
        return [{role, parts}];
      });
      
      // contextメッセージの非同期処理
      const asyncHistory: Content[] = [];
      for (const h of history) {
        if ((h as any)._contextInfo) {
          const {documentId, startPage, endPage, content} = (h as any)._contextInfo;
          try {
            const docMetaSnap = await db.collection("document_metadata").doc(documentId).get();
            if (!docMetaSnap.exists) {
              logger.warn(`document_metadata not found for id: ${documentId}`);
              continue;
            }
            const docMeta = docMetaSnap.data()!;
            const subject = docMeta.subject;
            const fileName = docMeta.file_name;
            if (!subject || !fileName) {
              logger.warn(`document_metadata missing subject or file_name for id: ${documentId}`);
              continue;
            }
            const fileBase = fileName.replace(/\.pdf$/i, "");
            const fileParts: Part[] = [];
            if (content && content.trim() !== "") {
              fileParts.push({text: content});
            }
            for (let page = startPage; page <= endPage; ++page) {
              const gcsUri = `gs://${FIREBASE_STORAGE_BUCKET}/split_documents/${subject}/${fileBase}/page${page}.pdf`;
              fileParts.push({fileData: {fileUri: gcsUri, mimeType: "application/pdf"}});
            }
            asyncHistory.push({role: h.role, parts: fileParts});
          } catch (e) {
            logger.error(`Error processing context message for document_id: ${documentId}`, e);
          }
        } else {
          asyncHistory.push(h);
        }
      }

      let partsForSendMessage: Part[] = [];
      let chatHistoryForGemini: Content[] = [];

      if (asyncHistory.length > 0 && asyncHistory[asyncHistory.length - 1].role === "user") {
        const lastUserMessage = asyncHistory[asyncHistory.length - 1];
        if (lastUserMessage.parts && lastUserMessage.parts.length > 0) {
          partsForSendMessage = lastUserMessage.parts;
        }
        chatHistoryForGemini = asyncHistory.slice(0, -1); 
      } else {
        const userMessagesFromHistory = asyncHistory.filter(h => h.role === "user");
        if (userMessagesFromHistory.length === 0) {
            logger.error("No user messages found to respond to for room: " + roomId);
            response.status(400).send({error: "No user messages to respond to in this room."});
            return;
        }
        const lastUserMessage = userMessagesFromHistory[userMessagesFromHistory.length - 1];
        if (lastUserMessage.parts && lastUserMessage.parts.length > 0) {
            partsForSendMessage = lastUserMessage.parts;
        }
        const lastUserMessageIndex = asyncHistory.lastIndexOf(lastUserMessage);
        chatHistoryForGemini = asyncHistory.slice(0, lastUserMessageIndex >= 0 ? lastUserMessageIndex : 0); // lastUserMessageIndexが-1の場合を考慮
        logger.warn(`History for room ${roomId} did not end with a user message. Using last known user message and prior history.`);
      }

      if (partsForSendMessage.length === 0) {
        logger.error("Could not determine parts for the latest user message in room: " + roomId);
        response.status(400).send({error: "No valid user message parts to respond to."});
        return;
      }

      logger.info(`Chat history length: ${chatHistoryForGemini.length}, Parts for send message: ${JSON.stringify(partsForSendMessage)}`);

      const chat = generativeModel.startChat({
        history: chatHistoryForGemini,
      });

      const result = await chat.sendMessage(partsForSendMessage);
      const modelResponse = result.response;

      if (!modelResponse || !modelResponse.candidates || modelResponse.candidates.length === 0) {
        logger.error("No response from Gemini", result);
        response.status(500).send({error: "Failed to get response from AI model"});
        return;
      }

      let aiResponseMessage = "";
      const firstCandidate = modelResponse.candidates[0];
      if (firstCandidate.content && 
          firstCandidate.content.parts && 
          firstCandidate.content.parts.length > 0 && 
          firstCandidate.content.parts[0].text) {
        aiResponseMessage = firstCandidate.content.parts[0].text;
      } else {
        logger.warn("Gemini response did not contain a text part or format was unexpected.", firstCandidate);
        aiResponseMessage = firstCandidate.content.parts.map(p => (p as {text?: string}).text || "").join(" ").trim() || "AIからの応答にテキストが含まれていませんでした。";
      }

      logger.info(`AI response: "${aiResponseMessage}"`);

      await db.collection("messages").add({
        room_id: roomId,
        content: aiResponseMessage,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        role: "model",
        type: "text", 
        user_id: "ai_model",
      });

      logger.info("AI response saved to Firestore");
      response.status(200).send({success: true, ai_response: aiResponseMessage});
    } catch (error) {
      logger.error("Error in generateResponseMobile", error);
      response.status(500).send({error: "Internal server error"});
    }
  }
);