import yaml
import sys

def check_yaml_syntax(file_path):
    try:
        with open(file_path, 'r') as file:
            yaml.safe_load(file)
        print(f"YAML syntax is valid for file: {file_path}")
    except yaml.YAMLError as e:
        print(f"YAML syntax error in file: {file_path}\n{e}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python check_yaml_syntax.py <path_to_yaml_file>")
        sys.exit(1)

    yaml_file_path = sys.argv[1]
    check_yaml_syntax(yaml_file_path)
    