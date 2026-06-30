// #define BLYNK_TEMPLATE_ID "TMPL3XoJ5M444"
#define BLYNK_TEMPLATE_ID "TMPL30x7m_3FK" //key2
// #define BLYNK_TEMPLATE_NAME "Sensor1"
#define BLYNK_TEMPLATE_NAME "Air Quality" //key2
// #define BLYNK_AUTH_TOKEN "UK_poqP4o6pq98xxPgBJUkQtWk0YWblg"
#define BLYNK_AUTH_TOKEN "hqZiF8mq_Sqp_t9FANHIrbDdbmFdWNx_" // key2

#define BLYNK_PRINT Serial
#include <ESP8266WiFi.h>
#include <BlynkSimpleEsp8266.h>

char ssid[] = "One";
char pass[] = "qwerty123";

BlynkTimer timer;

// Pin definitions
int Buzzer = D2;
int GAS_CTRL = D6;
int Oxygenmonitor = D7;

// ADC values
int adcValue1 = 0;
int adcValue2 = 0;

// Blynk states
int buzzerstate = 0;

// Alarm flags
bool gasAlarm = false;
bool oxygenAlarm = false;

// Thresholds
#define GAS_THRESHOLD 600
#define OXY_THRESHOLD 455

// ---------------- SETUP ----------------

void setup()
{
  Serial.begin(9600);
  Blynk.begin(BLYNK_AUTH_TOKEN, ssid, pass);

  pinMode(Buzzer, OUTPUT);
  pinMode(GAS_CTRL, OUTPUT);
  pinMode(Oxygenmonitor, OUTPUT);

  digitalWrite(Buzzer, LOW);
  digitalWrite(GAS_CTRL, LOW);
  digitalWrite(Oxygenmonitor, LOW);
}

// ---------------- LOOP ----------------

void loop()
{
  gas();        // Gas sensor reading
  oxygen();     // Oxygen sensor reading

  // -------- FINAL BUZZER DECISION --------
  if (buzzerstate == 1 || gasAlarm == true || oxygenAlarm == true)
  {


    digitalWrite(Buzzer, HIGH);
    Serial.println(buzzerstate);
    Serial.println(gasAlarm);
    Serial.println(oxygenAlarm);
  }
  else
  {
    digitalWrite(Buzzer, LOW);
  }
    

  Blynk.run();
}

// ---------------- BLYNK ----------------

BLYNK_WRITE(V5)   // Manual buzzer ON/OFF
{
  buzzerstate = param.asInt();
}

// ---------------- GAS SENSOR ----------------

void gas()
{
  gasAlarm = false;

  // Turn ON gas sensor
  digitalWrite(GAS_CTRL, HIGH);
  Serial.println("Gas Sensor ON");

  delay(200);              // relay + sensor settle time

  // 🔹 Flush previous ADC value
  analogRead(A0);
  delay(50);
  analogRead(A0);

  for (int i = 0; i < 5; i++)
  {
    adcValue1 = analogRead(A0);
     int gasDisplayValue = adcValue1 * 10;
    // if (adcValue1 > GAS_THRESHOLD)
    if (gasDisplayValue > GAS_THRESHOLD)
      gasAlarm = true;

    Serial.print("Gas ADC Value: ");
    Serial.println(gasDisplayValue);

    Blynk.virtualWrite(V1, gasDisplayValue);

    delay(2000);   // kept as requested
  }

  digitalWrite(GAS_CTRL, LOW);
  Serial.println("Gas Sensor OFF");
}

// ---------------- OXYGEN SENSOR ----------------

void oxygen()
{
  oxygenAlarm = false;

  // Turn ON oxygen sensor
  digitalWrite(Oxygenmonitor, HIGH);
  Serial.println("Oxygen Sensor ON");

  delay(200);              // relay + amplifier settle time

  // 🔹 Flush previous ADC value
  analogRead(A0);
  delay(50);
  analogRead(A0);

  for (int i = 0; i < 5; i++)
  {
    adcValue2 = analogRead(A0);

    if (adcValue2 < OXY_THRESHOLD)
      oxygenAlarm = true;

    Serial.print("Oxygen ADC Value: ");
    Serial.println(adcValue2);

    Blynk.virtualWrite(V3, adcValue2);

    delay(2000);   // kept as requested
  }

  digitalWrite(Oxygenmonitor, LOW);
  Serial.println("Oxygen Sensor OFF");
}