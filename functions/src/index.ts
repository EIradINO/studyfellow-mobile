/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

// 他のファイルで定義された関数をエクスポート
export * from "./process-document.js";
export * from "./generate-response-mobile.js";
export * from "./create-userdata.js";
// export * from "./create-userdata";
// Firebase Admin SDKの初期化やdbインスタンスは、
// 各関数ファイル内で個別に行うか、共通の初期化ファイルを作成してそこからインポートすることを検討してください。
// ここでは、process-document.ts に移動したため、index.ts からは削除します。  