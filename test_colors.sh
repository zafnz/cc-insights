#!/bin/bash
# Test script for xterm colors

echo -e "\033[1;31m===== XTERM COLOR TEST =====\033[0m"
echo -e "\033[30mBlack\033[0m \033[31mRed\033[0m \033[32mGreen\033[0m \033[33mYellow\033[0m \033[34mBlue\033[0m \033[35mMagenta\033[0m \033[36mCyan\033[0m \033[37mWhite\033[0m"
echo -e "\033[1;30mBright Black\033[0m \033[1;31mBright Red\033[0m \033[1;32mBright Green\033[0m \033[1;33mBright Yellow\033[0m"
echo -e "\033[1;34mBright Blue\033[0m \033[1;35mBright Magenta\033[0m \033[1;36mBright Cyan\033[0m \033[1;37mBright White\033[0m"
echo -e "\033[41m Red BG \033[0m \033[42m Green BG \033[0m \033[43m Yellow BG \033[0m \033[44m Blue BG \033[0m"
echo -e "\033[45m Magenta BG \033[0m \033[46m Cyan BG \033[0m \033[47m White BG \033[0m \033[100m Gray BG \033[0m"
echo -e "\033[4;34mUnderlined Blue\033[0m \033[7;32mReversed Green\033[0m \033[1;4;31mBold Underline Red\033[0m"
echo -e "\033[38;5;208mOrange (256)\033[0m \033[38;5;129mPurple (256)\033[0m \033[38;5;51mAqua (256)\033[0m \033[38;5;196mBright Red (256)\033[0m"
echo -e "\033[48;5;21m Blue BG 256 \033[0m \033[48;5;201m Pink BG 256 \033[0m \033[48;5;226m Yellow BG 256 \033[0m"
echo ""
echo "256 Color Palette (first 16):"
for i in {0..15}; do printf "\033[48;5;${i}m %3d \033[0m" $i; done; echo ""
echo ""
echo "Grayscale ramp (232-255):"
for i in {232..255}; do printf "\033[48;5;${i}m  \033[0m"; done; echo ""
echo ""
echo -e "\033[38;2;255;100;0mTrue Color RGB(255,100,0)\033[0m \033[38;2;0;200;255mRGB(0,200,255)\033[0m \033[38;2;180;0;255mRGB(180,0,255)\033[0m"
echo -e "\033[48;2;50;50;150m\033[38;2;255;255;0m Yellow on Purple (RGB) \033[0m"
echo -e "\033[1;32m✓ All colors rendered successfully!\033[0m"
read
