# respawned1

ResPAWnd GitHub Setup Instructions
Prerequisites — install these first

Android Studio: developer.android.com/studio
Flutter SDK: flutter.dev/docs/get-started/install/windows
Git: git-scm.com/download/win


Step 1: Get a GitHub Personal Access Token

Go to GitHub → profile picture → Settings
Scroll left to Developer settings → Personal access tokens → Tokens (classic)
Click Generate new token (classic)
Name it respawnd, set expiration to 90 days, check repo
Click Generate token and copy it immediately


Step 2: Clone the repo
Open PowerShell and run:
bashgit clone https://YOUR_GITHUB_USERNAME:YOUR_TOKEN@github.com/santosmarcus/respawned1.git
Replace YOUR_GITHUB_USERNAME and YOUR_TOKEN with your own.

Step 3: Open in Android Studio

Open Android Studio → Open
Navigate to the cloned respawned1 folder → click OK
Wait for Gradle to sync


Step 4: Install Flutter dependencies
In the Android Studio terminal (bottom tab):
bashflutter pub get

Step 5: Switch to your branch
Gabrielle:
bashgit checkout gabrielle
Austin:
bashgit checkout austin

Step 6: Daily workflow
bash# Start of every coding session — sync with dev first
git checkout dev
git pull origin dev
git checkout your-branch-name
git merge dev

# After coding
git add .
git commit -m "describe what you did"
git push origin your-branch-name

Step 7: Run the app
Connect an Android phone or start an emulator, then:
bashflutter run
