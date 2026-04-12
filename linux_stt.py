import speech_recognition as sr
import sys

def main():
    recognizer = sr.Recognizer()
    microphone = sr.Microphone()

    # Adjust for ambient noise once
    with microphone as source:
        recognizer.adjust_for_ambient_noise(source, duration=1)

    print("STT_READY", flush=True)

    while True:
        try:
            with microphone as source:
                audio = recognizer.listen(source, phrase_time_limit=10)
            
            # Use Google Speech Recognition (free, requires internet)
            # For pure offline we'd need pocketsphinx setup, but this works reliably for now.
            text = recognizer.recognize_google(audio)
            print(f"STT_RESULT:{text}", flush=True)
            
        except sr.UnknownValueError:
            pass  # Could not understand audio
        except sr.RequestError as e:
            print(f"STT_ERROR:{e}", flush=True)
        except KeyboardInterrupt:
            break
        except Exception as e:
            pass # Keep alive on other errors

if __name__ == "__main__":
    main()
