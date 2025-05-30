import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {VertexAI, Part, Content} from "@google-cloud/vertexai";

// Firebase Admin SDKの初期化（まだ初期化されていない場合）
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const PROJECT_ID = "studyfellow-42d35";
const FIREBASE_STORAGE_BUCKET = `${PROJECT_ID}.firebasestorage.app`;
const vertexAI = new VertexAI({project: PROJECT_ID, location: "us-central1"});
const generativeModel = vertexAI.getGenerativeModel({ model: "gemini-2.0-flash" });

export const generatePostResponseMobile = onRequest(
  {
    region: "asia-northeast1",
  },
  async (request, response) => {
    logger.info("generatePostResponseMobile function triggered", {structuredData: true});

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
      const { post_id } = request.body;
      if (!post_id) {
        response.status(400).send({error: "post_id is required"});
        return;
      }
      // 1. posts取得
      const postSnap = await db.collection("posts").doc(post_id).get();
      if (!postSnap.exists) {
        response.status(404).send({error: "post not found"});
        return;
      }
      const post = postSnap.data()!;
      const { content, document_id, start_page, end_page } = post;
      // context parts生成
      let contextParts: Part[] = [];
      if (document_id && typeof start_page === "number" && typeof end_page === "number") {
        const docMetaSnap = await db.collection("document_metadata").doc(document_id).get();
        if (docMetaSnap.exists) {
          const docMeta = docMetaSnap.data()!;
          const subject = docMeta.subject;
          const fileName = docMeta.file_name;
          if (subject && fileName) {
            const fileBase = fileName.replace(/\.pdf$/i, "");
            if (content && typeof content === "string" && content.trim() !== "") {
              contextParts.push({text: content});
            }
            for (let page = start_page; page <= end_page; ++page) {
              const gcsUri = `gs://${FIREBASE_STORAGE_BUCKET}/split_documents/${subject}/${fileBase}/page${page}.pdf`;
              contextParts.push({fileData: {fileUri: gcsUri, mimeType: "application/pdf"}});
            }
          }
        }
      } else if (content && typeof content === "string" && content.trim() !== "") {
        contextParts.push({text: content});
      }
      // historyの先頭
      const history: Content[] = [
        { role: "user", parts: contextParts }
      ];
      // 2. post_messages_to_ai取得
      const aiMsgSnap = await db.collection("post_messages_to_ai")
        .where("post_id", "==", post_id)
        .orderBy("created_at", "asc")
        .get();
      if (!aiMsgSnap.empty) {
        for (const doc of aiMsgSnap.docs) {
          const data = doc.data();
          const role = data.role === "user" || data.role === "model" ? data.role : "user";
          const type = data.type || "text";
          const parts: Part[] = [];
          if (type === "text") {
            if (data.content && typeof data.content === "string" && data.content.trim() !== "") {
              parts.push({text: data.content});
            }
          } else if (type === "image" || type === "file") {
            if (data.content && typeof data.content === "string" && data.content.trim() !== "") {
              parts.push({text: data.content});
            }
            const messageUserId = data.user_id;
            const fileName = data.file_name;
            const mimeType = data.mime_type;
            if (fileName && typeof fileName === "string" && 
                mimeType && typeof mimeType === "string" &&
                messageUserId && typeof messageUserId === "string") {
              const gcsUri = `gs://${FIREBASE_STORAGE_BUCKET}/chat_attachments/${messageUserId}/${post_id}/${fileName}`;
              parts.push({fileData: {fileUri: gcsUri, mimeType: mimeType}});
            }
          } else if (type === "context") {
            const documentId = data.document_id;
            const startPage = data.start_page;
            const endPage = data.end_page;
            const msgContent = data.content && typeof data.content === "string" ? data.content : "";
            if (documentId && typeof startPage === "number" && typeof endPage === "number") {
              const docMetaSnap = await db.collection("document_metadata").doc(documentId).get();
              if (docMetaSnap.exists) {
                const docMeta = docMetaSnap.data()!;
                const subject = docMeta.subject;
                const fileName = docMeta.file_name;
                if (subject && fileName) {
                  const fileBase = fileName.replace(/\.pdf$/i, "");
                  if (msgContent && msgContent.trim() !== "") {
                    parts.push({text: msgContent});
                  }
                  for (let page = startPage; page <= endPage; ++page) {
                    const gcsUri = `gs://${FIREBASE_STORAGE_BUCKET}/split_documents/${subject}/${fileBase}/page${page}.pdf`;
                    parts.push({fileData: {fileUri: gcsUri, mimeType: "application/pdf"}});
                  }
                }
              }
            }
          }
          if (parts.length > 0) {
            history.push({role, parts});
          }
        }
      }
      // Gemini呼び出し
      const lastUserMessage = history[history.length - 1];
      const previousHistory = history.slice(0, -1);
      const chat = generativeModel.startChat({ 
        history: previousHistory
      });
      const result = await chat.sendMessage(lastUserMessage.parts);
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
        aiResponseMessage = firstCandidate.content.parts.map((p: any) => p.text || "").join(" ").trim() || "AIからの応答にテキストが含まれていませんでした。";
      }
      // Geminiの返答をpost_messages_to_aiに保存
      await db.collection("post_messages_to_ai").add({
        post_id: post_id,
        content: aiResponseMessage,
        role: "model",
        type: "text",
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        user_id: post.user_id,
      });
      response.status(200).send({success: true, ai_response: aiResponseMessage});
    } catch (error) {
      logger.error("Error in generatePostResponseMobile", error);
      response.status(500).send({error: "Internal server error"});
    }
  }
); 