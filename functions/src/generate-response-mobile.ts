import {onRequest} from "firebase-functions/v2/https"; // v2のonRequestをインポート
import * as logger from "firebase-functions/logger";
import { GoogleGenAI } from "@google/genai";

// リージョンを指定 (v2ではonRequestのオプションで指定)
const region = "asia-northeast1"; // 例: 東京リージョン

// Gemini APIキーを環境変数から取得
const API_KEY = process.env.GEMINI_API_KEY;
if (!API_KEY) {
  logger.error("GEMINI_API_KEY is not set in environment variables.");
  // ここでエラーを投げるか、デフォルトの動作を定義するか検討
}

// Geminiクライアントの初期化
const genAI = API_KEY ? new GoogleGenAI({apiKey: API_KEY}) : null;

export const generateResponseMobile = onRequest(
  {
    region: region,
    secrets: ["GEMINI_API_KEY"], // Secret Managerから読み込むシークレット名を指定
    // 必要に応じて他のオプション (メモリ、タイムアウトなど) を追加
    // memory: "1GiB",
    // timeoutSeconds: 60,
  },
  async (request, response) => {
    logger.info("generateResponseMobile function triggered", { structuredData: true });

    // CORSヘッダーの設定
    response.set("Access-Control-Allow-Origin", "*"); // 本番環境ではより具体的なオリジンを指定してください
    response.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    // OPTIONSメソッド（pre-flightリクエスト）への対応
    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }

    // 実際の処理 (今回はHello World)
    // logger.info("Request body:", request.body);
    // logger.info("Query params:", request.query);

    response.status(200).send({ message: "Hello World from generate-response-mobile!" });
  }
); 