@ -1,289 +1,2 @@
# Ubuntu Touch for OnePlus 8 (instantnoodle)

## Contents
- [Ubuntu Touch Device Tree for the OnePlus 8 (instantnoodle)](#ubuntu-touch-device-tree-for-the-oneplus-8-instantnoodle)
  - [Contents](#contents)
- [Prerequisites and Warnings](#prerequisites-and-warnings)
  - [Setting up Your Build Environment](#setting-up-your-build-environment)
    - [How to Build](#how-to-build)
      - [How to Flash](#how-to-flash)
      - [Flashing Recovery](#flashing-recovery)
## Prerequisites and Warnings
> [!NOTE] 
> OnePlus 8 (instantnoodle).

> [!IMPORTANT]s
> [!CAUTION]
> This guide involves procedures like unlocking the bootloader, flashing firmware, and modifying system components. These actions can potentially lead to negative outcomes, such as voiding your warranty, bricking your device, or compromising its security. Proceed with full understanding of the risks and ensure you follow the instructions carefully.

## Setting up Your Build Environment
**For amd64 architecture (commonly referred to as 64 bit)**:

Docker-Compose:
```bash
git clone https://github.com/scotthowson/Portable-Docker-Ubuntu
cd Portable-Docker-Ubuntu
```

Modify any Environment Variable that you need.
```bash
nano .env
```

```bash
docker-compose build --no-cache                                                                                                 ─╯
docker-compose up -d
docker exec -it Ubuntu-20.04 bash
```

### How to Build

To build this project:
```bash
git clone https://github.com/scotthowson/halium_kernel_instantnoodle
cd halium_kernel_instantnoodle
chmod +x build.sh
./build.sh -b instantnoodle
./build/prepare-fake-ota.sh out/device_instantnoodle_usrmerge.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command Images/instantnoodle-a10
```
If built successfully, your system images will be in 'Images/instantnoodle-a10/'

## How to Flash
### Using System Partition
```bash
adb devices
adb reboot fastboot
fastboot delete-logical-partition product_a
fastboot flash boot boot.img
fastboot flash system system.img
fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
```

## Getting Started with SSH & Telnet!
First we will be setting the device to be called OnePlus-8
```bash
ip route show
# The device name will most likely resemble 'enp0s29u1u1'.
sudo sh -c 'ip link set down dev <devicename> && ip link set dev <devicename> name OnePlus-8 && ip link set up dev OnePlus-8'
# Once done we will run this command to verify that we see '192.168.2.0/24 dev OnePlus-8 proto kernel ...'
ip route show
```

### SSH Connection
```bash
sudo sh -c 'ip link set dev OnePlus-8 up && ip address add 10.15.19.82 dev OnePlus-8 && ip route add 10.15.19.100 dev OnePlus-8'

sudo ip address add 10.15.19.100/24 dev OnePlus-8
sudo ip link set OnePlus-8 up
ssh phablet@10.15.19.82
```

### Telnet Connection
```bash
sudo sh -c 'ip link set dev OnePlus-8 up && ip address add 192.168.2.20 dev OnePlus-8 && ip route add 192.168.2.15 dev OnePlus-8'

ip link set OnePlus-8 address 02:11:22:33:44:55
ip address add 10.15.19.100/24 dev OnePlus-8
ip link set OnePlus-8 up

ip r

telnet 192.168.2.15
```
### Tethering Internet Connection
Here’s how we can adjust the setup:
1. Remove the Incorrect Default Route

Remove the existing default route to avoid conflicts.

```bash
sudo ip route del default
```

2. Add the Correct Default Route

Add the correct default route pointing to the host machine.

```bash
sudo ip route add default via 10.15.19.100 dev usb0
```

3. Update DNS Configuration

Ensure the DNS servers are correctly set in /etc/resolv.conf:

```bash
sudo sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo sh -c 'echo "nameserver 8.8.4.4" >> /etc/resolv.conf'
cat /etc/resolv.conf
```

4. Test Connectivity

Test connectivity to ensure routing and DNS are correctly set up:

```bash
ping -c 4 8.8.8.8
ping -c 4 google.com
```

Full Example:

Here are the full commands to run in sequence on the phone:

```bash
sudo ip route del default
sudo ip route add default via 10.15.19.100 dev usb0
sudo sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo sh -c 'echo "nameserver 8.8.4.4" >> /etc/resolv.conf'
cat /etc/resolv.conf
ping -c 4 8.8.8.8
ping -c 4 google.com
```

Host Machine Configuration:

Ensure IP forwarding and correct IPTables settings on the host machine:
```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o eno2 -j MASQUERADE
sudo iptables -A FORWARD -i eno2 -o enp0s20f0u3 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i enp0s20f0u3 -o eno2 -j ACCEPT
```

## Troubleshooting
Common issues and their solutions will be listed [here](https://docs.ubports.com/en/latest/porting/configure_test_fix/index.html). If you encounter any problems, refer to this section for guidance.

```bash
# you can try to chroot the into rootfs and perform:
systemctl mask usb-moded
systemctl add-wants sysinit.target usb-tethering
systemctl add-wants sysinit.target usb-moded-ssh
systemctl mask usb-moded
systemctl enable usb-tethering
systemctl enable ssh
```

# OnePlus 8

![Halium 10.0](https://img.shields.io/badge/Halium-10.0-orange)
![instantnoodle](https://img.shields.io/badge/CodeName-instantnoodle-green)
![Installer](https://img.shields.io/badge/Installer-Available-brightgreen)
![Buy](https://img.shields.io/badge/Buy-Available-blue)

---

## Features & Usability

### Core Connectivity
**State: Basic support**

**Automated Usability (beta)**  
The device has basic data capabilities and can connect to mobile networks (as applicable), but currently offers minimal features, and some of the smart functionalities might not work yet. It can be a very nice second device.

### Actors
| Feature           | Status |
|-------------------|--------|
| Manual brightness | ✔      |
| Torchlight        | ✔      |
| Vibration         | ✔      |

### Camera
| Feature                       | Status |
|-------------------------------|--------|
| Flashlight                    | ✔      |
| Photo                         | ✔      |
| Video                         | ✔      |
| Switching between cameras     | ✔      |

### Cellular
| Feature                         | Status |
|---------------------------------|--------|
| Dual SIM functionality (Global Issue) | ⚠ |
| Carrier info, signal strength   | ✔      |
| Data connection                 | ✔      |
| Incoming, outgoing calls (Global Issue) | ⚠ |
| MMS in, out                     | ✔      |
| PIN unlock                      | ✔      |
| SMS in, out                     | ✔      |
| Change audio routings           | ✔      |
| Voice in calls                  | ✔      |
| Volume control in calls         | ✔      |

### Endurance
| Feature                  | Status |
|--------------------------|--------|
| 24+ hours battery lifetime | ✔      |
| 7+ days stability         | ✔      |

### GPU
| Feature                   | Status |
|---------------------------|--------|
| Boot into UI              | ✔      |
| Hardware video playback   | ✔      |

### Misc
| Feature                       | Status |
|-------------------------------|--------|
| AppArmor patches              | ✔      |
| Battery percentage            | ✔      |
| Offline charging              | ⚠      |
| Online charging               | ✔      |
| Recovery image                | ✔      |
| Reset to factory defaults     | ✔      |
| RTC time                      | ✔      |
| Shutdown / Reboot             | ✔      |
| Wireless External monitor     | ✔      |
| Waydroid                      | ✔      |

### Network
| Feature    | Status |
|------------|--------|
| Bluetooth  | ✔      |
| Flight mode| ✔      |
| Hotspot    | ✔      |
| NFC        | ✔      |
| WiFi       | ✔      |

### Sensors
| Feature                  | Status |
|--------------------------|--------|
| Automatic brightness     | ✔      |
| Fingerprint reader       | ✔      |
| GPS (Global Issue)       | ⚠      |
| Proximity                | ✔      |
| Rotation                 | ✔      |
| Touchscreen              | ✔      |
| Double touch to wake     | ✔      |

### Sound
| Feature                  | Status |
|--------------------------|--------|
| Earphones                | ✔      |
| Loudspeaker              | ✔      |
| Microphone               | ⚠      |
| Volume control           | ✔      |

### USB
| Feature                  | Status |
|--------------------------|--------|
| MTP access               | ✔      |
| ADB access               | ✔      |

## Feature Legend

- ✔ Working: Confirmed, depending on the maintenance
- ⚠ Not Working: If there is a link here, follow it to learn more
- ⚠ Partial: Working to some extent but with issues
- ⚠ Global Issue: Issue is not specific to this device

## Contributing
[Contributions](https://docs.ubports.com/en/latest/contribute/index.html) to this guide are welcome. If you have suggestions or corrections, please submit a pull request or open an issue on the GitHub repository.

## References and Credits
Acknowledgments to individuals or sources that have contributed to this guide.
[OnePlus Kebab repository](https://gitlab.com/DaniAsh551/oneplus-kebab) - [DaniAsh551](https://gitlab.com/DaniAsh551)

## Special Thanks
A heartfelt thank you to [DaniAsh551](https://gitlab.com/DaniAsh551) and their [OnePlus Kebab repository](https://gitlab.com/DaniAsh551/oneplus-kebab) for their invaluable assistance and patience throughout the development of this project. Their contributions and guidance have been instrumental in its success.

