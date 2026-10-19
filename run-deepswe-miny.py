# install datasets (uv or pip install in venv)
import subprocess
from datasets import load_dataset

# Configuration
MODEL_ID = "openai/gufo-qwen3.8-flash-next-tp2-q8"  # Prepended with openai/ to trigger the correct adapter
LOCAL_URL = "http://system76.local:4000/v1"
AGENT = "mini-swe-agent"
OUTPUT_DIR = "jobs"

def main():
    print("Fetching DeepSWE-mini task names from Hugging Face...")
    dataset = load_dataset("LocalLLaMA/deepswe-mini", split="test")
    task_names = dataset["task_name"]
    
    print(f"Found {len(task_names)} tasks to run locally.\n")
    
    for i, task in enumerate(task_names, start=1):
        print(f"[{i}/{len(task_names)}] Running task: {task}")
        task_path = f"deep-swe/tasks/{task}"
        
        # Build the command injecting the local endpoint parameters into the environment
        cmd = [
            "pier", "run",
            "-p", task_path,
            "--agent", AGENT,
            "--model", MODEL_ID,
            "--ae", f"OPENAI_API_BASE={LOCAL_URL}",
            "--ae", "OPENAI_API_KEY=local-secret-key",
            "-o", OUTPUT_DIR
        ]
        
        try:
            subprocess.run(cmd, check=True)
            print(f"Finished task: {task}\n")
        except subprocess.CalledProcessError as e:
            print(f"Error encountered while executing task {task}: {e}\n")
            continue

if __name__ == "__main__":
    main()

