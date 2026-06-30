# 🌍 AirGuard - Smart IoT-Based Environmental & Confined Space Air Safety System

> An IoT-based air quality and confined space monitoring system that detects hazardous gases and oxygen levels in real time, providing instant alerts and remote monitoring through a mobile application.

---

## 📖 Overview

AirGuard is a B.Tech Final Year Project developed to improve safety in confined spaces such as wells, underground tanks, mines, and industrial environments where hazardous gases and oxygen deficiency can pose serious risks.

The system continuously monitors environmental conditions using gas and oxygen sensors, sends live data to a mobile application via IoT, and automatically triggers safety alerts whenever dangerous conditions are detected.

---

## 🚀 Features

- 🌡️ Real-time air quality monitoring
- 🫁 Oxygen level monitoring
- ☁️ IoT-enabled wireless monitoring
- 📱 Mobile application for live data visualization
- 🔔 Instant alerts during hazardous conditions
- 🚨 Automatic buzzer/siren activation
- 🎛️ Manual buzzer control from the mobile application
- 📡 Remote monitoring using Wi-Fi connectivity

---

## 🛠️ Technologies Used

### Hardware
- ESP8266 (NodeMCU)
- MQ-135 Gas Sensor
- AO-03 Oxygen Sensor
- Relay Module
- Operational Amplifier
- Buzzer/Siren
- Power Supply

### Software
- Flutter
- Blynk IoT Platform
- Arduino IDE
- Embedded C/C++

---

## ⚙️ How It Works

1. MQ-135 and AO-03 sensors continuously monitor environmental conditions.
2. ESP8266 reads and processes sensor data.
3. Sensor readings are transmitted to the Blynk cloud using Wi-Fi.
4. The Flutter mobile application displays live air quality and oxygen levels.
5. If gas concentration exceeds safe thresholds or oxygen levels drop below the safe limit:
   - The buzzer is activated automatically.
   - The mobile application sends an alert.
6. Users can remotely monitor the environment and manually control the buzzer through the application.

---

## 🏗️ System Architecture

```
Gas & Oxygen Sensors
        │
        ▼
    ESP8266 Controller
        │
   Wi-Fi Communication
        │
        ▼
    Blynk Cloud Server
        │
        ▼
 Flutter Mobile App
        │
        ▼
 User Notifications & Remote Control
```

---

## 📱 Mobile Application

The mobile application provides:

- Live sensor readings
- Real-time notifications
- Hazard alerts
- Manual buzzer control
- Wireless monitoring from anywhere

---

## 🎯 Project Objectives

- Monitor harmful gas levels in real time.
- Detect oxygen deficiency in confined spaces.
- Improve worker safety.
- Prevent accidents caused by hazardous gases.
- Enable remote monitoring through IoT.

---

## 🔧 Components Used

| Component | Purpose |
|------------|---------|
| ESP8266 | Main microcontroller with Wi-Fi |
| MQ-135 | Air quality and harmful gas detection |
| AO-03 | Oxygen level detection |
| Relay Module | Sensor switching/control |
| Operational Amplifier | Signal conditioning |
| Buzzer | Emergency alarm |

---

## 📸 Project Images

> Add your project images here.

```
images/
├── hardware.jpg
├── circuit-diagram.png
├── mobile-app.png
├── prototype.jpg
└── system-architecture.png
```

---

## 📹 Demo

Add your demo video link here.

Example:

https://github.com/yourusername/AirGuard/assets/...

---

## 📂 Project Structure

```
AirGuard/
│
├── Arduino_Code/
├── Flutter_App/
├── Circuit_Diagram/
├── Images/
├── Documentation/
├── README.md
└── LICENSE
```

---

## 💡 Future Enhancements

- AI-based gas hazard prediction
- Cloud database for historical analysis
- Multi-gas detection (CO, LPG, Methane, NH₃)
- Smart ventilation automation
- SMS and Email alerts
- GPS-enabled emergency notification
- Portable wearable version

---

## 👨‍💻 Team

- Muhammed Anas A
- Sekkeena Khan PM
- Shahana Fathima B
- Sneha Somakumar

**Guide**

Ms. Grace  
Assistant Professor  
Department of Computer Science & Engineering  
Nehru College of Engineering and Research Centre

---

## 📄 License

This project is developed for academic purposes as part of the B.Tech Final Year Project.

---

## ⭐ Support

If you found this project useful, consider giving it a ⭐ on GitHub.
