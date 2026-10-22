# Connect Google Drive

Work why: Let Mac Island connect Google accounts and transfer files in both directions. Google requires an OAuth client that identifies the app. This release does not include a shared Google client.

You can use the installed app for all steps. You do not need to edit or keep the source code. An optional terminal guide is available at `scripts/setup-google-drive.sh`.

## 1. Create a Google Cloud project and enable Drive

Open the [Google Cloud project selector](https://console.cloud.google.com/projectselector2/home/dashboard). Create or select a project you control. In [Google Drive API settings](https://console.cloud.google.com/apis/library/drive.googleapis.com), select that project and enable the Google Drive API.

## 2. Configure the consent screen

Open [Google Auth Platform](https://console.cloud.google.com/auth/overview). Configure the app name, contact email, and audience. For personal use with an external app in Testing, add your Google account email under **Audience > Test users**. Add each account you plan to connect.

Under **Data Access**, add `https://www.googleapis.com/auth/drive`. Mac Island uses this scope to browse your Drive files and upload to the folder you choose. Review the scope in Google's consent screen before you connect.

Public distribution with a shared client can require Google's OAuth verification. A Google Workspace administrator can also limit access. In Testing, Google can expire refresh tokens after seven days; reconnect when needed. See [Google's desktop OAuth instructions](https://developers.google.com/identity/protocols/oauth2/native-app).

## 3. Create a Desktop app client

Open [Google Auth Platform > Clients](https://console.cloud.google.com/auth/clients). Select **Create client**, choose **Desktop app**, and name it **Mac Island**. Download its client JSON file.

Do not choose Web application. Mac Island uses a loopback callback on `127.0.0.1` and PKCE. You do not need to set up a public callback server.

Do not commit the downloaded JSON to GitHub. Do not paste its client secret into a chat. Keep the downloaded file private until you import it.

## 4. Import and connect in the app

1. Open **Mac Island** from Applications.
2. Select its capsule icon in the menu bar, then **Google Drive…**.
3. Select **Import OAuth JSON…** and choose the downloaded file.
4. Select **Connect Account**. Complete sign-in and consent in your browser.
5. Return to Mac Island. Select **Refresh** to load the account's files.

Repeat **Connect Account** for other accounts. The account picker switches between them. Credentials and account tokens are stored in macOS Keychain. **Disconnect Selected Account** removes the local connection. You can also revoke the app's access in [your Google account](https://myaccount.google.com/connections).

## Transfer files

Open a folder in the Google Drive window. Select **Add to Tray** on a file to download it. Google documents are exported to standard Office file formats. After download, drag the file from File Tray to another app.

To upload, put a local file into File Tray, open the destination folder in the Drive window, and select the file's upload button. You can also drag local files from Finder onto the window's upload area. This creates new Drive files. It does not remove local files or change sharing permissions.

No cloud transfer was tested during development because no OAuth client was supplied. The connection, token refresh, listing, export, download, and upload paths are implemented. Verify them with your own account before relying on transfers.
