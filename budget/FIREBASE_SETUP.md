# Firebase 配置指南

## 为什么需要 Firebase？
Cashew 使用 Firebase 实现云同步功能：
- **Firebase Firestore** - 数据存储和同步
- **Firebase Auth** - 用户认证（Google 登录）
- 使用 **Spark 免费计划**，个人记账完全够用，不需要付费

## 免费额度（Spark Plan）
- 存储：1 GiB
- 读取：50,000 次/天
- 写入：20,000 次/天
- 删除：20,000 次/天

> 个人记账每月几百条记录，永远不会超过免费额度。

## 创建自己的 Firebase 项目

### 第 1 步：创建项目
1. 打开 https://console.firebase.google.com
2. 点击「创建项目」
3. 输入项目名称（例如：`my-bookkeeping`）
4. 关闭 Google Analytics（可选）
5. 点击「创建」

### 第 2 步：注册 iOS 应用
1. 在项目控制台，点击「添加应用」→ iOS
2. 填写信息：
   - **iOS Bundle ID**: `com.budget.tracker-app`（或你自己的 Bundle ID）
   - **应用昵称**: 记账App
   - 不需要 App Store ID
3. 点击「注册应用」
4. **下载 GoogleService-Info.plist**
5. 将文件放到 `budget/ios/Runner/GoogleService-Info.plist`

### 第 3 步：启用 Firestore 数据库
1. 在 Firebase 控制台 → 构建 → Firestore Database
2. 点击「创建数据库」
3. 选择位置（亚洲建议选 `asia-east1`）
4. 选择「测试模式」（后续可改为安全规则）
5. 点击「启用」

### 第 4 步：启用认证
1. Firebase 控制台 → 构建 → Authentication
2. 点击「开始」
3. 选择「Google」登录提供商
4. 启用 Google 登录

### 第 5 步：配置 Flutter 项目
```bash
# 安装 Firebase CLI
npm install -g firebase-tools

# 登录 Firebase
firebase login

# 配置 FlutterFire
cd D:\py_code\测试记账app\budget
flutterfire configure
```

这个命令会自动更新 `lib/firebase_options.dart` 和 iOS/Android 配置文件。

## 如果不使用 Firebase（纯离线）
如果不需要云同步，可以注释掉 main.dart 中的 Firebase 初始化：
```dart
// await Firebase.initializeApp(
//   options: DefaultFirebaseOptions.currentPlatform,
// );
```

纯离线模式下数据只存储在本地 SQLite 数据库，可以通过导入/导出手动备份。
