#!/bin/bash


if [ "$EUID" -ne 0 ]; then
  echo "請使用 root 權限運行此腳本"
  echo "Please run this script with root privileges"
  exit
fi


echo " ######              ####     ##                ##                                  ##                ####"
echo "   ##               ##                                                                               ##"
echo "   ##     ## ###   #####    ####     ## ###   ####     ## ###    #####            ####      ######  #####     #####"
echo "   ##     ###  ##   ##        ##     ###  ##    ##     ###      ##                  ##     ##   ##   ##      ##"
echo "   ##     ##   ##   ##        ##     ##   ##    ##     ##       ##                  ##     ##   ##   ##      ##"
echo "   ##     ##   ##   ##        ##     ##   ##    ##     ##       ##                  ##      ######   ##      ##"
echo " ######   ##   ##   ##      ######   ##   ##  ######   ##        #####            ######        ##   ##       #####"
echo "                                                                                            #####"
echo

# 檢測操作系統
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
else
    OS=$(uname -s)
fi


echo "檢測到的操作系統：$OS"
echo "Detected operating system: $OS"
echo "安裝必要的軟件包..."
echo "Installing necessary packages..."

case "$OS" in
    "Ubuntu"|"Ubuntu "*|"Debian GNU/Linux"|"Debian")
        apt-get update
        apt-get install -y build-essential libjansson-dev nvidia-settings nvidia-cuda-toolkit
        ;;
    "Rocky Linux"|"CentOS Linux"|"Red Hat Enterprise Linux"|"Fedora")
        dnf install -y gcc make jansson-devel
        ;;
    *)
        echo "您的系統暫不支援：$OS"
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

echo "啟用 NVIDIA 持續模式..."
echo "Enabling NVIDIA persistent mode..."
nvidia-smi -pm 1


echo "Creating C program..."
cat > /usr/local/src/infinirc_gpu_fan_control.c << EOL
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <jansson.h>
#include <nvml.h>

#define CONFIG_FILE "/etc/infinirc_gpu_fan_control.conf"
#define CURVE_FILE "/etc/infinirc_gpu_fan_curve.json"
#define MAX_GPU_COUNT 8
#define MAX_FAN_COUNT 3
#define MAX_CURVE_POINTS 20

typedef struct {
    int temperature;
    int fan_speed;
} FanCurvePoint;

typedef struct {
    FanCurvePoint points[MAX_CURVE_POINTS];
    int point_count;
} FanCurve;

unsigned int device_count = 0;
volatile sig_atomic_t keep_running = 1;


void reset_fan_curve(void);
char* get_gpu_model(void);
void display_gpu_info(void);
int read_config(int *manual_speed);
void write_config(int is_manual, int speed);
FanCurve* read_fan_curve(void);
void write_fan_curve(FanCurve *curve);
void edit_fan_curve(int temp, int speed);
void show_fan_curve(void);
int get_gpu_fan_count(int gpu_index);
void set_fan_speed(int gpu_index, int fan_index, int speed);
int get_gpu_temp(nvmlDevice_t handle);
int adjust_fan_speed(int temp);
void show_help(void);
void list_gpus(void);
void enable_persistence_mode(void);
void write_config_for_gpu(const char* gpu_key, const char* mode, int speed);
void maintain_fan_settings(void);
void signal_handler(int signum);

void reset_fan_curve(void) {
    FanCurve default_curve = {
        .points = {
            {30, 30}, {40, 40}, {50, 50},
            {60, 60}, {70, 70}, {80, 100}
        },
        .point_count = 6
    };
    write_fan_curve(&default_curve);
    printf("風扇曲線已還原為預設值。\n");
    printf("Fan curve has been reset to default values.\n");
}

char* get_gpu_model(void) {
    nvmlDevice_t device;
    char *model = malloc(NVML_DEVICE_NAME_BUFFER_SIZE);
    if (nvmlDeviceGetHandleByIndex(0, &device) == NVML_SUCCESS &&
        nvmlDeviceGetName(device, model, NVML_DEVICE_NAME_BUFFER_SIZE) == NVML_SUCCESS) {
        return model;
    }
    free(model);
    return strdup("Unknown");
}

void display_gpu_info(void) {
    char *gpu_model = get_gpu_model();
    printf("\n==================================================\n");
    printf("GPU 信息 | GPU Information\n");
    printf("==================================================\n");
    printf("當前 GPU 型號：%s\n", gpu_model);
    printf("Current GPU model: %s\n", gpu_model);
    printf("==================================================\n\n");
    free(gpu_model);
}

int read_config(int *manual_speed) {
    FILE *fp = fopen(CONFIG_FILE, "r");
    if (fp == NULL) return 0;

    char buffer[10];
    if (fgets(buffer, sizeof(buffer), fp) != NULL) {
        buffer[strcspn(buffer, "\n")] = 0;
        if (strcmp(buffer, "auto") == 0) {
            fclose(fp);
            return 0;
        } else if (strcmp(buffer, "curve") == 0) {
            *manual_speed = -1;
            fclose(fp);
            return 1;
        } else if (atoi(buffer) >= 0 && atoi(buffer) <= 100) {
            *manual_speed = atoi(buffer);
            fclose(fp);
            return 1;
        }
    }
    fclose(fp);
    return 0;
}

void write_config(int is_manual, int speed) {
    FILE *fp = fopen(CONFIG_FILE, "w");
    if (fp == NULL) return;

    if (is_manual) {
        if (speed == -1) {
            fprintf(fp, "curve");
        } else {
            fprintf(fp, "%d", speed);
        }
    } else {
        fprintf(fp, "auto");
    }
    fclose(fp);
}

FanCurve* read_fan_curve(void) {
    json_error_t error;
    json_t *root = json_load_file(CURVE_FILE, 0, &error);
    if (!root) return NULL;

    FanCurve *curve = malloc(sizeof(FanCurve));
    curve->point_count = 0;

    const char *key;
    json_t *value;
    json_object_foreach(root, key, value) {
        int temp = atoi(key);
        int speed = json_integer_value(value);
        curve->points[curve->point_count].temperature = temp;
        curve->points[curve->point_count].fan_speed = speed;
        curve->point_count++;
        if (curve->point_count >= MAX_CURVE_POINTS) break;
    }

    json_decref(root);
    return curve;
}

void write_fan_curve(FanCurve *curve) {
    json_t *root = json_object();
    for (int i = 0; i < curve->point_count; i++) {
        char temp_str[4];
        snprintf(temp_str, sizeof(temp_str), "%d", curve->points[i].temperature);
        json_object_set_new(root, temp_str, json_integer(curve->points[i].fan_speed));
    }
    json_dump_file(root, CURVE_FILE, JSON_INDENT(4));
    json_decref(root);
}

void edit_fan_curve(int temp, int speed) {
    FanCurve *curve = read_fan_curve();
    if (curve == NULL) {
        curve = malloc(sizeof(FanCurve));
        curve->point_count = 0;
    }

    int index = -1;
    for (int i = 0; i < curve->point_count; i++) {
        if (curve->points[i].temperature == temp) {
            index = i;
            break;
        } else if (curve->points[i].temperature > temp) {
            index = i;
            break;
        }
    }

    if (index == -1) {
        index = curve->point_count;
    }

    if (index < curve->point_count && curve->points[index].temperature == temp) {
        curve->points[index].fan_speed = speed;
    } else {
        if (curve->point_count < MAX_CURVE_POINTS) {
            for (int i = curve->point_count; i > index; i--) {
                curve->points[i] = curve->points[i-1];
            }
            curve->points[index].temperature = temp;
            curve->points[index].fan_speed = speed;
            curve->point_count++;
        } else {
            printf("錯誤：風扇曲線點數已達到最大值 %d。\n", MAX_CURVE_POINTS);
            printf("Error: Fan curve points have reached the maximum of %d.\n", MAX_CURVE_POINTS);
            free(curve);
            return;
        }
    }

    write_fan_curve(curve);
    printf("已更新風扇曲線：%d°C -> %d%%\n", temp, speed);
    printf("Updated fan curve: %d°C -> %d%%\n", temp, speed);
    free(curve);
}

void show_fan_curve(void) {
    FanCurve *curve = read_fan_curve();
    if (curve) {
        printf("當前風扇曲線：\n");
        printf("Current fan curve:\n");
        printf("+--------------+-----------------+\n");
        printf("| 溫度(°C)     | 風扇速度(%%)     |\n");
        printf("| Temperature  | Fan Speed       |\n");
        printf("+--------------+-----------------+\n");
        for (int i = 0; i < curve->point_count; i++) {
            printf("| %-12d | %-15d |\n", curve->points[i].temperature, curve->points[i].fan_speed);
        }
        printf("+--------------+-----------------+\n");
        free(curve);
    } else {
        printf("未設置風扇曲線。\n");
        printf("Fan curve is not set.\n");
    }
}

int get_gpu_fan_count(int gpu_index) {
    char command[256];
    FILE *fp;
    char buffer[1024];
    int fan_count = 0;

    snprintf(command, sizeof(command), "nvidia-settings -q [gpu:%d]/GPUFanControlState -q [gpu:%d]/GPUTargetFanSpeed | grep -c 'Fan'", gpu_index, gpu_index);
    fp = popen(command, "r");
    if (fp == NULL) {
        printf("無法執行命令以獲取風扇數量\n");
        printf("Unable to execute command to get fan count\n");
        return 1;
    }

    if (fgets(buffer, sizeof(buffer), fp) != NULL) {
        fan_count = atoi(buffer);
    }
    pclose(fp);

    return fan_count > 0 ? fan_count : 1;
}

#include <unistd.h>
#include <fcntl.h>

void set_fan_speed(int gpu_index, int fan_index, int speed) {
    char command[512];
    FILE *fp;
    char buffer[1024];
    int original_stderr;


    original_stderr = dup(STDERR_FILENO);


    int dev_null = open("/dev/null", O_WRONLY);
    dup2(dev_null, STDERR_FILENO);
    close(dev_null);


    snprintf(command, sizeof(command), 
             "nvidia-settings -c :0 "
             "-a [gpu:%d]/GPUFanControlState=1 "
             "-a [fan:%d]/GPUTargetFanSpeed=%d", 
             gpu_index, gpu_index * 2 + fan_index, speed);
    
    system(command);


    dup2(original_stderr, STDERR_FILENO);
    close(original_stderr);

    printf("已設置 GPU %d 的風扇 %d 速度為 %d%%\n", gpu_index, fan_index, speed);
    printf("Set GPU %d fan %d speed to %d%%\n", gpu_index, fan_index, speed);


    snprintf(command, sizeof(command), 
             "nvidia-settings -c :0 -q [fan:%d]/GPUCurrentFanSpeed 2>/dev/null", 
             gpu_index * 2 + fan_index);
    
    fp = popen(command, "r");
    if (fp != NULL) {
        if (fgets(buffer, sizeof(buffer), fp) != NULL) {
            char *value = strchr(buffer, ':');
            if (value != NULL) {
                value++; 
                while (*value == ' ') value++; 
                printf("當前風扇速度：%s", value);
                printf("Current fan speed: %s", value);
            }
        }
        pclose(fp);
    }
}

void enable_persistence_mode() {
    for (unsigned int i = 0; i < device_count; i++) {
        char command[256];
        snprintf(command, sizeof(command), "nvidia-smi -i %d -pm 1 > /dev/null 2>&1", i);
        system(command);
    }

}

int get_gpu_temp(nvmlDevice_t handle) {
    unsigned int temp;
    if (nvmlDeviceGetTemperature(handle, NVML_TEMPERATURE_GPU, &temp) == NVML_SUCCESS) {
        return (int)temp;
    }
    return -1;
}

int adjust_fan_speed(int temp) {
    FanCurve *curve = read_fan_curve();
    if (curve) {
        for (int i = 0; i < curve->point_count - 1; i++) {
            if (temp >= curve->points[i].temperature && temp < curve->points[i+1].temperature) {
                int t1 = curve->points[i].temperature;
                int t2 = curve->points[i+1].temperature;
                int s1 = curve->points[i].fan_speed;
                int s2 = curve->points[i+1].fan_speed;
                free(curve);
                return s1 + (s2 - s1) * (temp - t1) / (t2 - t1);
            }
        }
        free(curve);
    }
    
    if (temp < 30) return 30;
    if (temp > 65) return 100;    
    float t = (temp - 30) / 30.0;
    int fan_speed = 30 + (int)(70 * t * t);
    return (fan_speed > 100) ? 100 : fan_speed;
}

void show_help(void) {
    printf("Infinirc GPU Fan Control (IGFC) 使用方法：\n");
    printf("Infinirc GPU Fan Control (IGFC) Usage:\n\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| 命令 / Command             | 描述 / Description                       |\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc auto                  | 設置為自動模式                           |\n");
    printf("|                            | Set to automatic mode                    |\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc curve                 | 使用自定義風扇曲線                       |\n");
    printf("|                            | Use custom fan curve                     |\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc curve <temp> <speed>  | 編輯風扇曲線                             |\n");
    printf("|                            | Edit fan curve                           |\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc curve show            | 顯示當前風扇曲線                         |\n");
    printf("|                            | Show current fan curve                   |\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc curve reset           | 還原預設風扇曲線                         |\n");
    printf("|                            | Reset fan curve to default               |\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc <speed>               | 設置所有GPU固定風扇速度（30-100）        |\n");
    printf("|                            | Set fixed fan speed for all GPUs (30-100)|\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc <gpu_index> <speed>   | 設置特定GPU固定風扇速度（30-100）        |\n");
    printf("|                            | Set fixed fan speed for specific GPU     |\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc list                  | 列出所有GPU及其編號                      |\n");
    printf("|                            | List all GPUs and their indices          |\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc status                | 顯示當前狀態                             |\n");
    printf("|                            | Show current status                      |\n");
    printf("+----------------------------+------------------------------------------+\n");
    printf("| igfc -h                    | 顯示此幫助信息                           |\n");
    printf("|                            | Show this help message                   |\n");
    printf("+----------------------------+------------------------------------------+\n");
}

void list_gpus(void) {
    unsigned int device_count;
    nvmlReturn_t result = nvmlDeviceGetCount(&device_count);
    if (result != NVML_SUCCESS) {
        printf("Failed to get device count: %s\n", nvmlErrorString(result));
        return;
    }

    printf("檢測到的 GPU 列表：\n");
    printf("List of detected GPUs:\n");
    for (unsigned int i = 0; i < device_count; i++) {
        nvmlDevice_t device;
        result = nvmlDeviceGetHandleByIndex(i, &device);
        if (result != NVML_SUCCESS) continue;

        char name[NVML_DEVICE_NAME_BUFFER_SIZE];
        result = nvmlDeviceGetName(device, name, NVML_DEVICE_NAME_BUFFER_SIZE);
        if (result != NVML_SUCCESS) {
            strcpy(name, "Unknown");
        }

        printf("GPU %u: %s\n", i, name);
    }
}
void write_config_for_gpu(const char* gpu_key, const char* mode, int speed) {
    json_t *root;
    json_error_t error;

    root = json_load_file(CONFIG_FILE, 0, &error);
    if (!root) {
        root = json_object();
    }

    json_t *gpu_config = json_object();
    json_object_set_new(gpu_config, "mode", json_string(mode));
    if (strcmp(mode, "manual") == 0) {
        json_object_set_new(gpu_config, "speed", json_integer(speed));
    }

    json_object_set_new(root, gpu_key, gpu_config);

    json_dump_file(root, CONFIG_FILE, JSON_INDENT(2));

    json_decref(root);
}
void maintain_fan_settings() {
    while (keep_running) {
        json_t *root;
        json_error_t error;

        root = json_load_file(CONFIG_FILE, 0, &error);
        if (!root) {
            root = json_object();
        }

        for (unsigned int i = 0; i < device_count; i++) {
            char gpu_key[20];
            snprintf(gpu_key, sizeof(gpu_key), "gpu%d", i);
            json_t *config_json = json_object_get(root, gpu_key);
            
            nvmlDevice_t device;
            nvmlDeviceGetHandleByIndex(i, &device);
            int temp = get_gpu_temp(device);
            int fan_count = get_gpu_fan_count(i);
            int fan_speed;

            if (json_is_object(config_json)) {
                const char *mode = json_string_value(json_object_get(config_json, "mode"));
                if (strcmp(mode, "manual") == 0) {
                    fan_speed = json_integer_value(json_object_get(config_json, "speed"));
                } else if (strcmp(mode, "curve") == 0) {
                    fan_speed = adjust_fan_speed(temp);
                } else {
                    fan_speed = adjust_fan_speed(temp);  
                }
            } else {
                fan_speed = adjust_fan_speed(temp);  
            }

            for (int j = 0; j < fan_count; j++) {
                set_fan_speed(i, j, fan_speed);
            }
        }

        json_decref(root);
        sleep(5);  
    }
}

void signal_handler(int signum) {
    if (signum == SIGTERM || signum == SIGINT) {
        printf("Received termination signal, exiting...\n");
        keep_running = 0;
    }
}


void show_status(void) {
    json_t *root;
    json_error_t error;

    root = json_load_file(CONFIG_FILE, 0, &error);
    if (!root) {
        printf("無法讀取配置文件\n");
        printf("Unable to read config file\n");
        return;
    }

    printf("\n==================================================\n");
    printf("GPU 狀態 | GPU Status\n");
    printf("==================================================\n");

    for (unsigned int i = 0; i < device_count; i++) {
        char gpu_key[20];
        snprintf(gpu_key, sizeof(gpu_key), "gpu%d", i);
        json_t *config_json = json_object_get(root, gpu_key);

        nvmlDevice_t device;
        nvmlDeviceGetHandleByIndex(i, &device);
        
        char name[NVML_DEVICE_NAME_BUFFER_SIZE];
        nvmlDeviceGetName(device, name, NVML_DEVICE_NAME_BUFFER_SIZE);

        int temp = get_gpu_temp(device);
        
        printf("GPU %d (%s):\n", i, name);
        
        if (json_is_object(config_json)) {
            const char *mode = json_string_value(json_object_get(config_json, "mode"));
            if (strcmp(mode, "manual") == 0) {
                int speed = json_integer_value(json_object_get(config_json, "speed"));
                printf("  模式: 固定轉速 %d%%\n", speed);
                printf("  Mode: Fixed speed %d%%\n", speed);
            } else if (strcmp(mode, "curve") == 0) {
                printf("  模式: 自定義曲線\n");
                printf("  Mode: Custom curve\n");
            } else {
                printf("  模式: 自動\n");
                printf("  Mode: Auto\n");
            }
        } else {
            printf("  模式: 自動\n");
            printf("  Mode: Auto\n");
        }
        
        printf("  溫度: %d°C\n", temp);
        printf("  Temperature: %d°C\n", temp);
        printf("\n");
    }

    json_decref(root);
}

int main(int argc, char *argv[]) {
    nvmlReturn_t result;
    result = nvmlInit();
    if (result != NVML_SUCCESS) {
        printf("初始化 NVML 失敗：%s\n", nvmlErrorString(result));
        printf("Failed to initialize NVML: %s\n", nvmlErrorString(result));
        return 1;
    }

    result = nvmlDeviceGetCount(&device_count);
    if (result != NVML_SUCCESS) {
        printf("獲取設備數量失敗：%s\n", nvmlErrorString(result));
        printf("Failed to get device count: %s\n", nvmlErrorString(result));
        nvmlShutdown();
        return 1;
    }

    printf("==================================================\n");
    printf("GPU 檢測 | GPU Detection\n");
    printf("==================================================\n");
    printf("檢測到 %u 個 GPU\n", device_count);
    printf("Detected %u GPUs\n", device_count);
    printf("==================================================\n");

    enable_persistence_mode();

    if (argc == 1 || strcmp(argv[1], "-h") == 0) {
        show_help();
    } else if (strcmp(argv[1], "status") == 0) {
        show_status();
    } else if (strcmp(argv[1], "auto") == 0) {
        for (unsigned int i = 0; i < device_count; i++) {
            char gpu_key[20];
            snprintf(gpu_key, sizeof(gpu_key), "gpu%d", i);
            write_config_for_gpu(gpu_key, "auto", 0);
            char command[256];
            snprintf(command, sizeof(command), 
                     "nvidia-settings -c :0 -a [gpu:%d]/GPUFanControlState=0 2>/dev/null", i);
            system(command);
        }
        printf("所有 GPU 風扇控制設置為自動模式。\n");
        printf("All GPU fan control set to automatic mode.\n");
    } else if (strncmp(argv[1], "curve", 4) == 0) {
        if (argc == 2) {
            for (unsigned int i = 0; i < device_count; i++) {
                char gpu_key[20];
                snprintf(gpu_key, sizeof(gpu_key), "gpu%d", i);
                write_config_for_gpu(gpu_key, "curve", 0);
            }
            printf("所有 GPU 風扇控制設置為曲線模式。\n");
            printf("All GPU fan control set to curve mode.\n");
        } else if (argc == 4 && atoi(argv[2]) >= 0 && atoi(argv[3]) >= 0) {
            int temp = atoi(argv[2]);
            int speed = atoi(argv[3]);
            if (temp >= 0 && temp <= 100 && speed >= 0 && speed <= 100) {
                edit_fan_curve(temp, speed);
            } else {
                printf("無效輸入。溫度和速度都應在 0 到 100 之間。\n");
                printf("Invalid input. Both temperature and speed should be between 0 and 100.\n");
            }
        } else if (argc == 3) {
            if (strcmp(argv[2], "show") == 0) {
                show_fan_curve();
            } else if (strcmp(argv[2], "reset") == 0) {
                reset_fan_curve();
            } else {
                printf("無效的曲線命令。使用 'show' 或 'reset'。\n");
                printf("Invalid curve command. Use 'show' or 'reset'.\n");
                show_help();
            }
        } else {
            printf("無效的曲線命令。\n");
            printf("Invalid curve command.\n");
            show_help();
        }
    } else if (strcmp(argv[1], "list") == 0) {
        list_gpus();
    } else if (atoi(argv[1]) != 0 || strcmp(argv[1], "0") == 0) {
        int gpu_index = -1;
        int speed = -1;
        
        if (argc == 2) {
            speed = atoi(argv[1]);
            gpu_index = -1;  // 表示所有 GPU
        } else if (argc == 3) {
            gpu_index = atoi(argv[1]);
            speed = atoi(argv[2]);
        }

        if (speed >= 0 && speed <= 100) {
            if (gpu_index == -1) {
                for (unsigned int i = 0; i < device_count; i++) {
                    char gpu_key[20];
                    snprintf(gpu_key, sizeof(gpu_key), "gpu%d", i);
                    write_config_for_gpu(gpu_key, "manual", speed);
                    int fan_count = get_gpu_fan_count(i);
                    for (int j = 0; j < fan_count; j++) {
                        set_fan_speed(i, j, speed);
                    }
                }
            } else if (gpu_index >= 0 && gpu_index < (int)device_count) {
                char gpu_key[20];
                snprintf(gpu_key, sizeof(gpu_key), "gpu%d", gpu_index);
                write_config_for_gpu(gpu_key, "manual", speed);
                int fan_count = get_gpu_fan_count(gpu_index);
                for (int j = 0; j < fan_count; j++) {
                    set_fan_speed(gpu_index, j, speed);
                }
            } else {
                printf("無效的 GPU 索引。請使用 'igfc list' 查看可用的 GPU。\n");
                printf("Invalid GPU index. Use 'igfc list' to see available GPUs.\n");
                show_help();
            }
        } else {
            printf("無效輸入。使用 0 到 100 之間的數字。\n");
            printf("Invalid input. Use a number between 0 and 100.\n");
            show_help();
        }
    } else {
        printf("無效的命令：%s\n", argv[1]);
        printf("Invalid command: %s\n", argv[1]);
        show_help();
    }

    nvmlShutdown();
    return 0;
}
EOL


echo "Compiling C program..."
gcc -o /usr/local/bin/infinirc_gpu_fan_control /usr/local/src/infinirc_gpu_fan_control.c -I/usr/local/cuda/include -L/usr/local/cuda/lib64 -lnvidia-ml -ljansson


echo "Creating command alias..."
echo "alias igfc='sudo /usr/local/bin/infinirc_gpu_fan_control'" >> /etc/bash.bashrc


echo "Creating systemd service file..."
cat > /etc/systemd/system/infinirc-gpu-fan-control.service << EOL
[Unit]
Description=Infinirc GPU Fan Control Service
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/infinirc_gpu_fan_control
Restart=always

[Install]
WantedBy=multi-user.target  
EOL

echo "創建默認風扇曲線..."
echo "Creating default fan curve..."
cat > /etc/infinirc_gpu_fan_curve.json << EOL
{
    "30": 30,
    "40": 40,
    "50": 55,
    "60": 65,
    "70": 85,
    "80": 100
}
EOL

cat > /etc/infinirc_gpu_fan_curve.json.README << EOL
# 風扇曲線文件格式 / Fan curve file format:
# ----------------------------------------
# {
#     "溫度": 風扇速度,
#     "temperature": fan_speed,
#     ...
# }
#
# 溫度單位為攝氏度，風扇速度為百分比
# Temperature is in Celsius, fan speed is in percentage

+----------+------------+
| 溫度 (°C) | 風扇速度 (%) |
| Temp (°C) | Fan Speed  |
+----------+------------+
|    30    |     30     |
|    40    |     40     |
|    50    |     55     |
|    60    |     65     |
|    70    |     85     |
|    80    |    100     |
+----------+------------+
EOL

echo "啟用並啟動服務..."
echo "Enabling and starting service..."
systemctl daemon-reload
systemctl enable infinirc-gpu-fan-control.service
systemctl start infinirc-gpu-fan-control.service

cat << EOL

====================================================================
           Infinirc GPU Fan Control 安裝完成
           Infinirc GPU Fan Control Installation Complete
====================================================================

服務狀態 / Service Status: 已啟動 / Started

使用指南 / Usage Guide:
+----------------------------+------------------------------------------+
| 命令 / Command             | 描述 / Description                       |
+----------------------------+------------------------------------------+
| igfc auto                  | 設置為自動模式                           |
|                            | Set to automatic mode                    |
+----------------------------+------------------------------------------+
| igfc curve                 | 使用自定義風扇曲線                       |
|                            | Use custom fan curve                     |
+----------------------------+------------------------------------------+
| igfc curve <temp> <speed>  | 編輯風扇曲線                             |
|                            | Edit fan curve                           |
+----------------------------+------------------------------------------+
| igfc curve show            | 顯示當前風扇曲線                         |
|                            | Show current fan curve                   |
+----------------------------+------------------------------------------+
| igfc curve reset           | 還原預設風扇曲線                         |
|                            | Reset fan curve to default               |
+----------------------------+------------------------------------------+
| igfc <speed>               | 設置所有GPU固定風扇速度（30-100）        |
|                            | Set fixed fan speed for all GPUs (30-100)|
+----------------------------+------------------------------------------+
| igfc <gpu_index> <speed>   | 設置特定GPU固定風扇速度（30-100）        |
|                            | Set fixed fan speed for specific GPU     |
+----------------------------+------------------------------------------+
| igfc list                  | 列出所有GPU及其編號                      |
|                            | List all GPUs and their indices          |
+----------------------------+------------------------------------------+
| igfc status                | 顯示當前狀態                             |
|                            | Show current status                      |
+----------------------------+------------------------------------------+
| igfc -h                    | 顯示此幫助信息                           |
|                            | Show this help message                   |
+----------------------------+------------------------------------------+


注意：請登出並重新登入以使 'igfc' 命令生效。
Note: Please log out and log back in for the 'igfc' command to be available.

====================================================================
EOL

echo "重新啟動服務..."
echo "Restarting the service..."
systemctl restart infinirc-gpu-fan-control.service
systemctl enable infinirc-gpu-fan-control.service  
