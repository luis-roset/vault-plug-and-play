import signal
import sys
import time

# Flag to indicate if the script should exit
should_exit = False

def handle_exit(signum, frame):
    global should_exit
    print("\nSeñal recibida, saliendo del programa...")
    should_exit = True

# Register signal handlers for SIGINT (Ctrl+C) and SIGTERM
signal.signal(signal.SIGINT, handle_exit)
signal.signal(signal.SIGTERM, handle_exit)

while not should_exit:
    print("Haciendo cosas!")
    for _ in range(10):
        if should_exit:
            break
        time.sleep(1)

print("Programa terminado.")
sys.exit(0)
