import {onRequest} from "firebase-functions/v2/https"; // v2のonRequestをインポート
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin"; // firebase-adminをインポート
import {VertexAI} from "@google-cloud/vertexai"; // Vertex AI SDKをインポート

// Firebase Admin SDKの初期化（まだ初期化されていない場合）
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

// Vertex AIの初期化
// TODO: ご自身のプロジェクトIDとロケーションを設定してください
const PROJECT_ID = "studyfellow-42d35"; // 例: "my-gcp-project"
const LOCATION = "asia-northeast1"; // 例: "us-central1"
const MODEL_NAME = "gemini-1.5-flash"; // 使用するモデル

const vertexAI = new VertexAI({project: PROJECT_ID, location: LOCATION});
const generativeModel = vertexAI.getGenerativeModel({
  model: MODEL_NAME,
  // 必要に応じてgenerationConfigやsafetySettingsを設定
  // generationConfig: {
  //   maxOutputTokens: 256,
  //   temperature: 0.2,
  //   topP: 0.8,
  //   topK: 40,
  // },
  // safetySettings: [
  //   {
  //     category: HarmCategory.HARM_CATEGORY_HARASSMENT,
  //     threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
  //   },
  // ],
});

export const generateResponseMobile = onRequest(
  { 
    region: "asia-northeast1",
    // 必要に応じてメモリなどのオプションを設定
    // memory: "1GiB",
    // timeoutSeconds: 60,
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
      const {room_id: roomId} = request.body;

      if (!roomId) {
        logger.error("Room ID is missing in the request body");
        response.status(400).send({error: "Room ID is required"});
        return;
      }
      logger.info(`Processing request for room_id: ${roomId}`);

      // 1. room_idからroomを検索 (今回は直接messagesを検索するので不要だが、将来的にroom情報が必要な場合)
      // const roomDoc = await db.collection("rooms").doc(roomId).get();
      // if (!roomDoc.exists) {
      //   logger.error(`Room with ID ${roomId} not found`);
      //   response.status(404).send({error: "Room not found"});
      //   return;
      // }

      // 2. created_atが一番新しいユーザーメッセージを取得
      const messagesSnapshot = await db.collection("messages")
        .where("room_id", "==", roomId)
        .where("role", "==", "user") // ユーザーからのメッセージのみを対象
        .orderBy("created_at", "desc")
        .limit(1)
        .get();

      if (messagesSnapshot.empty) {
        logger.info(`No user messages found in room ${roomId}`);
        response.status(200).send({message: "No user messages to respond to"});
        return;
      }

      const latestMessage = messagesSnapshot.docs[0].data();
      const userMessageContent = latestMessage.content;

      if (!userMessageContent || typeof userMessageContent !== "string") {
        logger.error("Latest message content is empty or not a string", latestMessage);
        response.status(400).send({error: "Invalid message content"});
        return;
      }

      logger.info(`Latest user message: "${userMessageContent}"`);

      // 3. そのメッセージに対する返答をGeminiを用いて作成
      const prompt = `ユーザー: ${userMessageContent}\nAI:`; // シンプルなプロンプト例
      logger.info(`Sending prompt to Gemini: "${prompt}"`);

      const resp = await generativeModel.generateContent(prompt);
      const modelResponse = resp.response;
      
      if (!modelResponse || !modelResponse.candidates || modelResponse.candidates.length === 0) {
        logger.error("No response from Gemini model", resp);
        response.status(500).send({error: "Failed to get response from AI model"});
        return;
      }
      
      // 最初の候補のテキスト部分を取得
      // candidates[0].content.parts[0].text の存在を確認
      let aiResponseMessage = "";
      if (modelResponse.candidates[0].content && 
          modelResponse.candidates[0].content.parts && 
          modelResponse.candidates[0].content.parts.length > 0 &&
          modelResponse.candidates[0].content.parts[0].text) {
        aiResponseMessage = modelResponse.candidates[0].content.parts[0].text;
      } else {
        logger.error("Gemini response format is unexpected or text is missing", modelResponse.candidates[0]);
        // 安全なフォールバックメッセージ
        aiResponseMessage = "AIからの応答を取得できませんでした。"; 
      }

      logger.info(`Generated AI response: "${aiResponseMessage}"`);

      // 4. role=modelとしてmessagesに返答を保存
      await db.collection("messages").add({
        room_id: roomId,
        content: aiResponseMessage,
        created_at: admin.firestore.FieldValue.serverTimestamp(), // Firestoreのサーバータイムスタンプを使用
        role: "model",
        type: "text", // AIの応答はテキストタイプと仮定
        user_id: "ai_model", // AIを示す固定のID (または null)
        // file_name や file_url はAI応答には通常不要なのでnullまたは省略
      });

      logger.info("AI response successfully saved to Firestore");
      response.status(200).send({success: true, message: "AI response generated and saved.", ai_response: aiResponseMessage});
    } catch (error) {
      logger.error("Error in generateResponseMobile function", error);
      response.status(500).send({error: "Internal server error"});
    }
  }
);