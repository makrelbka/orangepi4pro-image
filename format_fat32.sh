#!/bin/bash

# Скрипт для форматирования диска (FAT32/ExFAT/HFS+/APFS/NTFS)
# Использование: ./format_fat32.sh [путь_к_диску]

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Скрипт форматирования диска ===${NC}\n"

# Доступные форматы (diskutil + ntfs-3g)
declare -a FORMAT_ARRAY
declare -a FORMAT_NAMES
declare -a FORMAT_DESCRIPTIONS

FORMAT_ARRAY[1]="FAT32"
FORMAT_NAMES[1]="FAT32"
FORMAT_DESCRIPTIONS[1]="FAT32 (для PS2, старых устройств, до 32GB)"

FORMAT_ARRAY[2]="MS-DOS"
FORMAT_NAMES[2]="MS-DOS"
FORMAT_DESCRIPTIONS[2]="MS-DOS FAT (совместимость с Windows/Mac)"

FORMAT_ARRAY[3]="ExFAT"
FORMAT_NAMES[3]="ExFAT"
FORMAT_DESCRIPTIONS[3]="ExFAT (для больших файлов >4GB, Windows/Mac)"

FORMAT_ARRAY[4]="HFS+"
FORMAT_NAMES[4]="HFS+"
FORMAT_DESCRIPTIONS[4]="Mac OS Extended (только для Mac)"

FORMAT_ARRAY[5]="APFS"
FORMAT_NAMES[5]="APFS"
FORMAT_DESCRIPTIONS[5]="Apple File System (только для Mac, macOS 10.13+)"

FORMAT_ARRAY[6]="NTFS"
FORMAT_NAMES[6]="NTFS"
FORMAT_DESCRIPTIONS[6]="NTFS (через ntfs-3g, в основном для Windows)"

# Выбор формата
echo -e "${YELLOW}Доступные форматы:${NC}"
for i in $(seq 1 6); do
    printf "  %d) %-10s - %s\n" "$i" "${FORMAT_NAMES[$i]}" "${FORMAT_DESCRIPTIONS[$i]}"
done

echo ""
echo -e "${YELLOW}Введите номер формата (1-6) [по умолчанию: 1 (FAT32)]: ${NC}"
read -r format_number
format_number=${format_number:-1}

# Проверка корректности ввода
if ! [[ "$format_number" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Ошибка: Введите число!${NC}"
    exit 1
fi

if [ "$format_number" -lt 1 ] || [ "$format_number" -gt 6 ]; then
    echo -e "${RED}Ошибка: Неверный номер формата!${NC}"
    exit 1
fi

SELECTED_FORMAT="${FORMAT_ARRAY[$format_number]}"
SELECTED_FORMAT_NAME="${FORMAT_NAMES[$format_number]}"

echo -e "${GREEN}Выбран формат: $SELECTED_FORMAT_NAME${NC}\n"

# Получение списка дисков с размерами
echo -e "${YELLOW}Доступные диски:${NC}"
declare -a DISK_ARRAY
declare -a DISK_NAMES
declare -a DISK_SIZES
declare -a DISK_TYPES

INDEX=1
for disk in $(diskutil list | grep -E "^/dev/disk[0-9]+" | awk '{print $1}'); do
    DISK_INFO=$(diskutil info "$disk" 2>/dev/null)
    SIZE=$(echo "$DISK_INFO" | grep "Disk Size" | awk -F': ' '{print $2}' | awk '{print $1, $2}')
    TYPE=$(echo "$DISK_INFO" | grep "Device / Media Name" | awk -F': ' '{print $2}')
    if [ -z "$TYPE" ]; then
        TYPE=$(echo "$DISK_INFO" | grep "Volume Name" | awk -F': ' '{print $2}' | head -1)
    fi
    if [ -z "$TYPE" ]; then
        TYPE="Unknown"
    fi
    
    DISK_ARRAY[$INDEX]="$disk"
    DISK_NAMES[$INDEX]="$disk"
    DISK_SIZES[$INDEX]="$SIZE"
    DISK_TYPES[$INDEX]="$TYPE"
    
    if [ -n "$SIZE" ]; then
        printf "  %d) %-15s %-20s %s\n" "$INDEX" "$disk" "$SIZE" "$TYPE"
    else
        printf "  %d) %s\n" "$INDEX" "$disk"
    fi
    INDEX=$((INDEX + 1))
done

echo ""
echo -e "${RED}⚠ ВНИМАНИЕ: Все данные на выбранном диске будут удалены!${NC}"
echo ""

# Выбор диска по номеру
if [ -n "$1" ]; then
    # Если диск указан как аргумент, используем его напрямую
    DISK="$1"
    if [[ "$DISK" =~ ^/dev/disk[0-9]+$ ]]; then
        DISK_RAW="${DISK}"
    elif [[ "$DISK" =~ ^/dev/disk[0-9]+s[0-9]+$ ]]; then
        DISK_RAW=$(echo "$DISK" | sed 's/s[0-9]*$//')
    else
        echo -e "${RED}Ошибка: Неверный формат диска. Используйте /dev/diskX${NC}"
        exit 1
    fi
else
    # Запрос номера диска у пользователя
    if [ $((INDEX - 1)) -eq 1 ]; then
        echo -e "${YELLOW}Введите номер диска (1) [по умолчанию: 1]: ${NC}"
        read -r disk_number
        disk_number=${disk_number:-1}
    else
        echo -e "${YELLOW}Введите номер диска (1-$((INDEX - 1))): ${NC}"
        read -r disk_number
    fi
    
    # Проверка корректности ввода
    if ! [[ "$disk_number" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Ошибка: Введите число!${NC}"
        exit 1
    fi
    
    if [ "$disk_number" -lt 1 ] || [ "$disk_number" -ge "$INDEX" ]; then
        echo -e "${RED}Ошибка: Неверный номер диска!${NC}"
        exit 1
    fi
    
    DISK_RAW="${DISK_ARRAY[$disk_number]}"
fi

# Проверка существования диска
if [ ! -e "$DISK_RAW" ]; then
    echo -e "${RED}Ошибка: Диск $DISK_RAW не найден!${NC}"
    exit 1
fi

# Показываем информацию о выбранном диске
echo ""
echo -e "${YELLOW}Выбранный диск:${NC}"
diskutil info "$DISK_RAW" | grep -E "Device Node|Disk Size|Volume Name"

# Запрос имени тома
echo ""
echo -e "${YELLOW}Введите имя тома (или нажмите Enter для имени по умолчанию): ${NC}"
read -r volume_name

# Установка имени по умолчанию в зависимости от формата
if [ -z "$volume_name" ]; then
    case "$format_number" in
        1) volume_name="USB" ;;
        2) volume_name="USB" ;;
        3) volume_name="USB" ;;
        4) volume_name="Mac" ;;
        5) volume_name="Mac" ;;
        6) volume_name="USB_NTFS" ;;
    esac
    echo -e "${YELLOW}Используется имя по умолчанию: $volume_name${NC}"
fi

# Финальное подтверждение
echo ""
echo -e "${RED}Вы уверены, что хотите отформатировать $DISK_RAW в $SELECTED_FORMAT_NAME?${NC}"
echo -e "${RED}Имя тома: $volume_name${NC}"
echo -e "${RED}Все данные на этом диске будут удалены! (yes/no) [по умолчанию: no]: ${NC}"
read -r confirmation
confirmation=${confirmation:-no}

if [ "$confirmation" != "yes" ] && [ "$confirmation" != "y" ]; then
    echo "Операция отменена."
    exit 0
fi

# Размонтирование диска
echo ""
echo -e "${YELLOW}Размонтирование диска...${NC}"
diskutil unmountDisk "$DISK_RAW" || true

# Форматирование
echo ""
echo -e "${YELLOW}Форматирование диска в $SELECTED_FORMAT_NAME...${NC}"
echo -e "${YELLOW}Это может занять несколько минут...${NC}"
echo ""

if [ "$SELECTED_FORMAT_NAME" = "NTFS" ]; then
    # NTFS через ntfs-3g (mkntfs)

    # Проверим, что mkntfs доступен
    if ! command -v mkntfs >/dev/null 2>&1; then
        echo -e "${RED}Ошибка: mkntfs (ntfs-3g) не найден!${NC}"
        echo -e "${YELLOW}Установите ntfs-3g, например:${NC}"
        echo "  brew install --cask macfuse"
        echo "  brew install ntfs-3g"
        exit 1
    fi

    echo -e "${YELLOW}Создание чистой разметки под NTFS...${NC}"
    sudo diskutil eraseDisk free NONE "$DISK_RAW"

    echo -e "${YELLOW}Создание одного раздела под NTFS...${NC}"
    sudo diskutil partitionDisk "$DISK_RAW" MBR MS-DOS "$volume_name" 100%

    # Находим только что созданный раздел (MS-DOS)
    PARTITION_DEV=$(diskutil list "$DISK_RAW" | awk '/MS-DOS/ {print $1; exit}')

    if [ -z "$PARTITION_DEV" ]; then
        echo -e "${RED}Не удалось найти раздел под NTFS!${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Размонтирование раздела перед форматированием...${NC}"
    diskutil unmount "$PARTITION_DEV" >/dev/null 2>&1 || true

    RAW_PARTITION_DEV="/dev/r$(basename "$PARTITION_DEV")"

    echo -e "${YELLOW}Форматирование раздела в NTFS через mkntfs...${NC}"
    sudo mkntfs -F -L "$volume_name" -c 32k "$RAW_PARTITION_DEV"

    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Форматирование в NTFS завершено успешно!${NC}"
        echo ""
        echo -e "${GREEN}Раздел $PARTITION_DEV отформатирован в NTFS с меткой '$volume_name'${NC}"
        DISK_RAW="$PARTITION_DEV"
    else
        echo ""
        echo -e "${RED}Ошибка при форматировании в NTFS!${NC}"
        exit 1
    fi
else
    # Обычные форматы через diskutil
    if sudo diskutil eraseDisk "$SELECTED_FORMAT" "$volume_name" "$DISK_RAW"; then
        echo ""
        echo -e "${GREEN}✓ Форматирование завершено успешно!${NC}"
        echo ""
        echo -e "${GREEN}Диск отформатирован в $SELECTED_FORMAT_NAME с меткой '$volume_name'${NC}"
    else
        echo ""
        echo -e "${RED}Ошибка при форматировании!${NC}"
        exit 1
    fi
fi

# Показываем информацию о отформатированном диске
echo ""
echo -e "${YELLOW}Информация о отформатированном диске:${NC}"
diskutil info "$DISK_RAW" | grep -E "Device Node|File System|Volume Name|Disk Size"

echo ""
echo -e "${GREEN}Готово! Диск готов к использованию.${NC}"
