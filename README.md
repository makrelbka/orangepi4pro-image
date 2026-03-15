# orangepi4pro-image

Отдельная директория для сборки и записи кастомного образа `Orange Pi 4 Pro`.

Внутри:
- `build-image.sh` — сборка `kernel` или полного `image` через Docker
- `flash-sd.sh` — запись `.img` на SD-карту
- `images/` — сюда кладется готовый `.img` для записи
- `output/` — сюда складываются артефакты сборки

## Что собирается

Целевая платформа:
- Board: `orangepi4pro`
- Branch: `legacy`
- Release: `jammy`
- Kernel: `5.15.147`
- Дополнение: `CONFIG_TUN=m`

Скрипт сборки повторяет рабочую схему, на которой уже был собран образ:
- Docker volume для case-sensitive source tree
- `ubuntu:22.04` внутри контейнера
- фиксы для старого `u-boot`
- привилегированный контейнер для финальной сборки `.img`

## Требования

На хосте:
- Docker
- локальная директория `../orangepi-build`

Если `orangepi-build` еще не клонирован:

```bash
git clone --depth=1 https://github.com/orangepi-xunlong/orangepi-build
```

Структура рядом должна быть такой:

```text
orangepi/
├── orangepi-build/
└── orangepi4pro-image/
```

## Сборка полного образа

```bash
cd orangepi4pro-image
./build-image.sh image
```

Результат:
- `output/output/images/Orangepi4pro_.../*.img`

## Сборка только kernel пакетов

```bash
cd orangepi4pro-image
./build-image.sh kernel
```

Результат:
- `output/output/debs/`

## Дополнительные аргументы сборки

Можно передавать любые дополнительные аргументы `orangepi-build` после режима:

```bash
./build-image.sh image CLEAN_LEVEL=make,oldcache
./build-image.sh kernel BUILD_KSRC=yes
```

## Подготовка образа к записи

Скопируй нужный `.img` в папку `images/`:

```bash
cp output/output/images/Orangepi4pro_*/Orangepi4pro_*.img images/
```

## Запись на SD-карту

```bash
cd orangepi4pro-image
./flash-sd.sh
```

Скрипт:
- покажет найденные `.img`
- покажет доступные диски
- попросит явное подтверждение
- запишет образ на выбранную SD-карту

На macOS используется `diskutil` и запись в `/dev/rdiskX`.
На Linux используется `lsblk` и `dd`.

## Проверка после загрузки

На Orange Pi:

```bash
grep CONFIG_TUN /boot/config-$(uname -r)
sudo modprobe tun
ls -l /dev/net/tun
```

Ожидаемо:

```text
CONFIG_TUN=m
```

и `/dev/net/tun` должен существовать.

## Замечания

- `output/` специально оставлен внутри этой директории, чтобы артефакты были локальны для проекта
- `images/` не очищается автоматически
- если Docker Desktop на macOS ломает runtime, сначала чини Docker, потом запускай сборку
