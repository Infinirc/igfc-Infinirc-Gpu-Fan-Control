# Infinirc GPU Fan Control (IGFC)

Infinirc GPU Fan Control (IGFC) 是一個用於 NVIDIA GPU 的風扇控制工具。它允許用戶自定義風扇曲線，設置固定風扇速度，或使用自動模式。

Infinirc GPU Fan Control (IGFC) is a fan control tool for NVIDIA GPUs. It allows users to customize fan curves, set fixed fan speeds, or use automatic mode.

## 功能 / Features

- 自定義風扇曲線 / Custom fan curve
- 固定風扇速度 / Fixed fan speed
- 自動模式 / Automatic mode
- 多 GPU 支持 / Multi-GPU support
- 實時溫度監控 / Real-time temperature monitoring

## 安裝 / Installation

1. 克隆此倉庫 / Clone this repository:
git clone https://github.com/yourusername/infinirc-gpu-fan-control.git
Copy
2. 進入目錄 / Enter the directory:
cd infinirc-gpu-fan-control
Copy
3. 運行安裝腳本 / Run the installation script:
sudo bash install.sh
Copy
## 使用方法 / Usage

使用 `igfc` 命令來控制您的 GPU 風扇。以下是一些常用命令：

Use the `igfc` command to control your GPU fans. Here are some common commands:

- `igfc auto`: 設置為自動模式 / Set to automatic mode
- `igfc curve`: 使用自定義風扇曲線 / Use custom fan curve
- `igfc <speed>`: 設置所有 GPU 固定風扇速度（30-100）/ Set fixed fan speed for all GPUs (30-100)
- `igfc status`: 顯示當前狀態 / Show current status
- `igfc -h`: 顯示幫助信息 / Show help message

## 系統要求 / System Requirements

- NVIDIA GPU
- Linux 操作系統 / Linux operating system
- NVIDIA 驅動程序 / NVIDIA drivers
- `nvidia-settings` 工具 / `nvidia-settings` tool

## 許可證 / License

本項目採用 MIT 許可證。詳情請見 [LICENSE](LICENSE) 文件。

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## 貢獻 / Contributing

歡迎貢獻！請閱讀 [CONTRIBUTING.md](CONTRIBUTING.md) 了解如何參與本項目。

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute to this project.

## 支持 / Support

如果您在使用過程中遇到任何問題，請開啟一個 issue。

If you encounter any problems while using this tool, please open an issue.