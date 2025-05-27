import * as functions from "firebase-functions";
import * as logger from "firebase-functions/logger";

// リージョンを指定 (例: "asia-northeast1" 東京)
const region = "asia-northeast1";

export const generateResponseMobile = functions
  .region(region) // リージョン指定
  .https.onRequest(async (request, response) => {
    logger.info("generateResponseMobile function triggered", { structuredData: true });

    // CORSヘッダーの設定 (Flutter Webやローカルテスト時に必要になる場合がある)
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (request.method === "OPTIONS") {
      // pre-flightリクエストへの対応
      response.status(204).send("");
      return;
    }

    // ここでリクエストボディからデータを取得したり、何らかの処理を行う
    // const data = request.body;
    // logger.info("Request body:", data);

    response.status(200).send({ message: "Hello World from generate-response-mobile!" });
  }); 