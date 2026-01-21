# SafeRoute MVP

## Project Structure
- **backend/**: FastAPI server for routing, hazards, and speed zones.
- **mobile_app/**: Flutter application for navigation.

## 🚀 How to Run

### 1. Start the Backend
*(Current Status: Running in background)*

If you need to restart it:
```powershell
cd backend
./venv/Scripts/Activate.ps1
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```
Server will be at: `http://localhost:8000` (or `http://10.0.2.2:8000` from Android Emulator).

### 2. Run the Mobile App
Open a **new terminal** (leaving the backend running).

```powershell
cd mobile_app
flutter pub get
flutter run
```

### 3. Physical Device Setup (Important)
If you are running the app on a **real Android phone** via USB:
1. Connect via USB.
2. Enable USB Debugging.
3. Run this command to forward the backend port:
   ```powershell
   adb reverse tcp:8000 tcp:8000
   ```
4. Now the phone can access the backend at `http://127.0.0.1:8000` (or `localhost`). 
   *Note: You may need to update `lib/services/api_service.dart` to use `127.0.0.1` instead of `10.0.2.2` if `10.0.2.2` doesn't work on your specific device setup via adb reverse.*

## 🕹️ Demo Features
- **Search**: Enter "San Francisco" to simulate a route.
- **Simulate Drive**: The app uses your **real GPS layout**. Use a location spoofer or drive around to see speed updates.
- **Hazards**: Tap the ⚠️ button to report.
- **Authority Mode**: Open Drawer -> Authority Mode -> Login (`admin`/`admin123`). Tap map to add verified hazards.
