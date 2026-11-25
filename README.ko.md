<h1 align="center"><img alt="unkernel" src="assets/logo-wordmark.svg" width="400"></h1>

**진짜 Linux 커널을 WebAssembly로 컴파일했습니다. 셸이 1초도 안 되어 부팅됩니다.**

<p align="center">
  <a href="https://unkernel.dev/"><b>체험하기</b></a> ·
  <a href="#-성능">성능</a> ·
  <a href="#-진짜-커널">기능</a> ·
  <a href="#-터미널에서-실행하기">CLI</a> ·
  <a href="#-동작-원리">동작 원리</a> ·
  <a href="#-벤치마크">벤치마크</a> ·
  <a href="#-javascript에서-사용하기">JavaScript SDK</a>
</p>

> 한국어 번역입니다. 원문은 [README.md](README.md)를 참고하세요.

unkernel은 실제 MMU를 갖춘 Linux 7.x를 단일 wasm 모듈로 빌드한 것입니다. 커널(시스템 콜, 스케줄러, 메모리 관리, ext4, TCP/IP)은 에뮬레이션이 아니라 컴파일된 코드이므로, 프로그램은 예외적인 경계 사례까지 Linux 본연의 동작을 그대로 얻습니다. 에뮬레이션되는 것은 사용자 프로그램뿐입니다. 수정하지 않은 aarch64(arm64) Linux 바이너리를 그대로 사용하므로 Alpine과 Debian 패키지가 있는 그대로 동작합니다.

[페이지를 열면](#-브라우저에서-사용하기) 셸, 패키지 관리자, 영속 디스크, 인터넷 연결, 소리가 나는 화면을 갖춘 Linux 머신을 얻습니다. 모든 것이 기기 위에서 완전히 동작하며 설치할 것도 서버도 없습니다. 모든 계층이 오픈 소스입니다. 설계는 [동작 원리](#-동작-원리)에서 설명합니다.

<p align="center">
  <img alt="Linux 프로그램이 kwemu에서 실행됩니다. kwemu는 Linux 커널에 연결된 aarch64 CPU로, 함께 unkernel.wasm으로 빌드되어 JavaScript SDK와 통신합니다" src="assets/architecture.svg" width="760">
</p>

## ⚡ 성능

시스템이 느리게 느껴지는 상당 부분은 커널에 있습니다. 프로세스 시작, 시스템 콜, 페이지 폴트, 파일·네트워크 I/O가 여기에 해당하며, unkernel에서는 이 경로가 wasm 속도로 동작합니다.

- **부팅**: 커널은 시작 후 약 70 ms에 `/init`에 도달하고, `node` 실행 후 0.3 s에 Alpine 프롬프트가 나타납니다. 페이지는 약 10 MB를 내려받고, Alpine은 48 MiB의 게스트 메모리로 부팅됩니다.
- **시스템 콜은 네이티브에 가까운 비용**: `getppid`는 약 170 ns(네이티브 110 ns, qemu-system에서는 1.7 µs), 64바이트 `read`는 약 170 ns(네이티브 160 ns).
- **fork는 네이티브 속도**: fork + exit + wait에 약 60 µs가 걸립니다. 네이티브는 약 70 µs, qemu-system은 1.2 ms입니다.
- **사용자 코드를 위한 JIT**: 자주 실행되는 aarch64 코드(OpenSSL이 사용하는 AES, PMULL, SHA 명령 포함)는 실행 중에 wasm으로 컴파일됩니다. 이를 통해 셸 루프는 인터프리터만 사용할 때보다 1.6배, `sort`는 2.3배 빨라지고, 게스트의 OpenSSL은 AES-128-GCM을 약 100 MB/s, SHA-256을 약 160 MB/s로 처리합니다.

시스템 콜과 fork 수치는 2026-11-14에 측정했습니다(프로젝트가 처음 사용한 riscv64 사용자 공간 기준이지만 커널을 지나는 경로는 동일합니다). JIT 수치는 2026-11-18입니다. CPU를 많이 쓰는 프로그램은 네이티브보다 크게 느립니다. 메인 인덱스에 대한 `apk search`는 약 0.8 s, `apk add python3`는 약 3.4 s가 걸립니다. 전체 수치는 [벤치마크](#-벤치마크)에 있습니다.

## 🐧 진짜 커널

프로그램이 의지하는 것, 즉 `/proc`와 `epoll`부터 cgroups와 overlayfs까지 모두 서버에서와 같이 동작합니다. 같은 코드를 실행하기 때문입니다.

- **진짜 MMU**(`arch/wasm`, Sv48 페이지 테이블): `fork`, `mmap`, copy-on-write, 공유 메모리, 스레드, 시그널이 하드웨어에서와 같이 동작합니다. 프로그램이 `vfork`로 제한되는 NOMMU 포트가 아닙니다.
- **Linux 자체 파일 시스템**: ext4, overlayfs, tmpfs, loop 장치, FUSE, 9p(호스트에서 프로그램이 제공하는 파일 시스템을 [마운트](#호스트-파일-마운트)할 수 있음). 루트 파일 시스템은 overlay로, 읽기 전용 배포판 이미지 위에 사용자의 변경 사항이 올라가 영속 ext4 디스크에 저장됩니다. 따라서 다시 불러와도 변경이 유지되고, 안전 모드로 망가진 시스템을 복구할 수 있습니다.
- **Linux 자체 TCP/IP 스택**: DHCP와 DNS를 지원하며, 호스트의 소켓이나 Wisp 프록시를 통해 인터넷에 연결됩니다([네트워크 추가](#네트워크-추가)).
- **cgroups, 네임스페이스, userfaultfd, fanotify, TUN**: systemd가 Ubuntu 26.10을 `multi-user.target`까지 부팅할 수 있을 정도입니다.
- **장치**: [프레임버퍼(`/dev/fb0`), evdev 키보드·마우스·터치, ALSA와 `/dev/dsp`를 통한 사운드](#화면-입력-사운드), [AF_VSOCK](#vsock으로-통신하기), 호스트와의 [공유 메모리](#공유-메모리).
- **aarch64 사용자 공간**: ARMv8.0-A에 FP와 AdvSIMD, 그리고 AES, PMULL, SHA1, SHA2, SHA512, SHA3, CRC32, LSE 원자 연산 확장이 포함되어 있어 배포판 바이너리와 OpenSSL의 하드웨어 AES·GHASH·SHA 경로가 수정 없이 동작합니다. aarch64는 모든 배포판의 일급 포트이므로 전체 최신 패키지 저장소를 그대로 사용할 수 있습니다.

[알려진 한계](#-알려진-한계)에 아직 빠진 기능이 정리되어 있습니다.

## 🧰 이렇게 쓸 수 있습니다

- **[Linux 셸을 어디에나 휴대](#-브라우저에서-사용하기).** Chrome, Edge, Firefox, Safari에서 Alpine Linux 3.24가 동작하며 모바일도 지원합니다. Alpine의 일반 미러에서 `apk add`로 무엇이든 설치할 수 있습니다. `htop`처럼 설치되지 않은 명령을 입력하면 패키지가 자동으로 설치됩니다. apk는 약 4배 빠르므로 처음에는 `main` 저장소만 켜 두고, `community`가 필요할 때 처음으로 추가됩니다.
- **실제 런타임과 도구 실행**: Node와 npm, Python, OpenSSL, curl, `wget`을 배포판에서 그대로 사용합니다. Debian 13도 Alpine과 같은 방식으로 부팅됩니다(`--distro debian`). apt 사용 가능.
- **[그래픽과 사운드 프로그램 작성](#화면-입력-사운드)**: `/dev/fb0`, evdev, ALSA 대상. 소리가 나는 작은 게임 `glimmer`를 시도해 보세요.
- **[앱에 Linux 내장](#-javascript에서-사용하기)**: 의존성 없는 TypeScript SDK로, [`unkernel`](https://www.npmjs.com/package/unkernel) 패키지로 배포됩니다. 같은 커널 파일이 Node와 모든 지원 브라우저에서 실행되고, [워커에서 실행](#워커에서-실행하기)도 가능합니다. [디스크](#디스크-추가)는 로컬 ext4 이미지, http(s)로 범위 요청해 가져오는 이미지, IndexedDB의 영속 디스크 중 골라 쓸 수 있습니다. SDK는 MIT 라이선스이고 폐쇄 엔진이나 라이선스 키가 없으므로 제품에 포함해 원하는 곳에서 호스팅할 수 있습니다.
- **게스트와 통신**: 각자 자기 pty와 셸을 가진 [터미널 세션](#프로그램-실행), 게스트에 마운트되는 [호스트 디렉터리와 메모리 파일 시스템](#호스트-파일-마운트), [vsock 바이트 스트림](#vsock으로-통신하기), [제로카피 공유 메모리](#공유-메모리)를 사용하며 중간에 네트워크가 필요 없습니다.
- **스크립트와 테스트**: [CLI](#-터미널에서-실행하기)가 시간에 맞춰 입력을 입력하고, 시간 초과 시 멈추며, 게스트 종료 결과를 종료 코드로 보고합니다.

## 🌐 브라우저에서 사용하기

**[unkernel.dev](https://unkernel.dev/)**를 여세요. 약 10 MB 다운로드 후 데스크톱이 나타나고, Terminal 창에 셸이 있습니다. 변경 사항은 브라우저에 저장됩니다. Dock에서 앱을 엽니다(Mac은 ⌘K, 그 외에는 Ctrl-Shift-O). Settings에 옵션과 디스크 내보내기·초기화가 있고, System에 진단 정보가 있습니다. 터미널 탭에서 Ctrl-A n(또는 Mac에서 ⌘A n)이나 `+`로 새 터미널을 열 수 있으며 최대 9개까지 가능합니다. Ctrl-A와 숫자로 전환하고, Ctrl-A ?로 모든 단축키를 봅니다. 기본 배경화면은 [Lorem Picsum](https://picsum.photos/)의 무작위 사진이라 페이지를 불러올 때마다 picsum.photos에서 가져옵니다. 기본 배경화면이나 프리셋(Settings > Desktop)을 쓰면 이 요청이 없습니다.

페이지는 몇 가지 URL 파라미터를 받습니다:

| 파라미터 | 동작 |
| --- | --- |
| `?mem=512` | 게스트 메모리(MiB) |
| `?append=...` | 추가 커널 명령줄 |
| `?net=0` | 네트워크 없이 부팅 |
| `?wisp=wss://...` | 자체 [Wisp](https://github.com/MercuryWorkshop/wisp-protocol) 프록시 사용 |
| `?jit=0` | 인터프리터만 사용 |
| `?data=0` | 영속 디스크 없음, 매번 새 시스템 |
| `?worker=0` | 커널을 페이지 스레드에서 실행(기본값: 페이지가 cross-origin isolated이면 Web Worker) |
| `?cpus=2` | 지정한 수의 CPU로 부팅, 각 CPU는 Web Worker(기본값: 기기 스레드 수의 절반, 데스크톱 최대 4, Firefox와 모바일은 2 — 이 경우 페이지가 SMP 커널을 쓰고 cross-origin isolated여야 함; `?cpus=1`: CPU 1개) |
| `?gl=0` | 게스트 GL 비활성화(기본값 Debian에서는 활성 — 게스트의 Mesa가 브라우저 WebGL2로 렌더링, 아래 참조) |

Debian에서는 게스트가 GPU를 받습니다(`/dev/dri`, Settings, Guest GL): Mesa의 virgl 드라이버가 브라우저의 WebGL2로 그립니다. 그 아래 렌더러는 게스트 프로그램이 처음 GL을 사용할 때만 내려받고, System > Environment의 Guest GL 항목이 GPU 이름을 알려줍니다(SwiftShader 같은 소프트웨어 렌더러는 표시됨). Mesa는 게스트에 설치되어 있으며 함께 배포되지 않습니다:

```sh
sudo apt-get install -y mesa-utils libegl-mesa0 libgles2 kmscube
eglinfo -B -p gbm                 # OpenGL ES 렌더러: virgl (<your GPU>)
kmscube                           # 화면에 표시 (Enter로 종료)
sudo apt-get install -y xvfb xauth glmark2-es2-x11
xvfb-run -a -s "-screen 0 640x480x24" glmark2-es2   # 프레임 레이트
```

Wayland 앱은 페이지의 창으로 나타납니다: `wland foot`(또는 런처의 foot 타일)이 게스트에서 wland 릴레이를 시작하고 앱을 그에 맞춰 실행합니다. [wland](https://github.com/pithings/wland)의 컴포지터는 페이지에서 실행되며 앱의 픽셀을 게스트 메모리에서 직접 읽습니다. 각 앱 창은 페이지 데스크톱의 창이고, Ctrl-A w로 다른 창과 전환합니다.

```sh
sudo apt-get install -y foot fonts-dejavu-core
wland foot
```

브라우저는 raw TCP 소켓을 열 수 없으므로 Wisp 프록시를 통해 인터넷에 연결합니다. 기본 프록시는 알려진 출처만 받으므로, 페이지를 다른 곳에서 호스팅한다면 `?wisp=`에 자체 프록시를 지정하세요.

| 브라우저 | 상태 |
| --- | --- |
| Chrome / Edge 137+ (데스크톱 및 Android) | ✅ 동작 |
| Firefox 153+ | ✅ 동작 |
| macOS의 Safari 27+, iOS/iPadOS 27의 모든 브라우저 | ✅ 동작 |
| [JSPI](#-동작-원리)를 지원하지 않는 모든 브라우저 | 페이지가 무엇이 빠졌는지 알려줌 |

## 💻 터미널에서 실행하기

```sh
npx unkernel
```

Alpine이 부팅되고 호스트 소켓으로 네트워크에 연결됩니다. 종료하려면 **Ctrl-]**를 누르세요. 패키지에는 커널과 작은 기본 시스템이 들어 있습니다. 첫 실행 시 해당 버전의 GitHub 릴리스에서 Alpine 이미지(약 4 MB)를 내려받아 `~/.cache/unkernel`에 보관합니다.

```sh
npx unkernel --distro debian                 # Debian 13 (약 57 MB, 한 번만 다운로드)
npx unkernel --distro none                   # 배포판 없음: 기본 셸(busybox)
npx unkernel --data my-data.img              # 변경 사항을 /data 디스크에 영속 저장(첫 사용 시 생성)
npx unkernel --display --sound               # 프레임버퍼와 사운드 카드
npx unkernel --mem 1024 --no-net             # 메모리 늘림, 네트워크 없음
npx unkernel --mount .:/work                 # 현재 디렉터리를 게스트의 /work에 (:ro는 읽기 전용)
npx unkernel --forward 8000:80               # 호스트 127.0.0.1:8000 → 게스트 포트 80
npx unkernel --timeout 60 --input '{8}uname -a\n{2}poweroff\n'   # 스크립트: 대기, 입력, 대기, 입력
npx unkernel --help                          # 나머지 옵션
```

`--data`가 없으면 루트 파일 시스템의 변경은 메모리에만 유지되고 종료 시 사라집니다. 있으면 배포판별로 `/data/distros/<name>/`에 저장됩니다. `--distro`에는 이미지 파일이나 http(s) URL도 넣을 수 있고, `UNKERNEL_CACHE_DIR`로 다운로드 캐시 위치를 바꿀 수 있습니다.

종료 코드: 0은 전원 끄기, 1은 halt 또는 부팅 실패, 2는 재시작, 124는 시간 초과, 253은 커널 패닉, 254는 wasm trap, 255는 치명적 오류입니다. CLI는 [JavaScript SDK](#-javascript에서-사용하기) 위에 만들어졌고, `--mount`는 [호스트 마운트](#호스트-파일-마운트), `--forward`는 [`vm.connect()`](#vsock으로-통신하기)를 사용합니다.

## 🔍 동작 원리

"브라우저의 Linux" 프로젝트는 대체로 세 가지 접근 중 하나를 취합니다:

- **전체 PC를 에뮬레이션**(커널 포함). 정확하지만 느립니다. 모든 시스템 콜과 페이지 폴트가 에뮬레이션된 하드웨어를 거치기 때문입니다.
- **CPU를 에뮬레이션하고 시스템 콜을 재구현**. 프로그램은 보통 JIT와 함께 에뮬레이션된 CPU에서 실행되고, 런타임이 시스템 콜에 응답합니다. Linux 커널이 전혀 없으므로 빠르지만, 런타임이 구현한 범위까지만 지원합니다.
- **프로그램을 wasm으로 컴파일**해 MMU 없는 커널이나 POSIX 호출을 제공하는 런타임에서 실행합니다. 빠르지만 네이티브 프로그램을 다시 빌드해야 하고, `fork`와 MMU가 필요한 기능은 깨지거나 근사치로 동작합니다.

unkernel은 각각의 장점만 취합니다. 실제 Linux 커널이 wasm 네이티브 속도로 실행되고, 수정되지 않은 바이너리가 진짜 MMU 아래에서 동작합니다.

| 접근 방식 | 커널 | 사용자 공간 | MMU |
| --- | --- | --- | --- |
| 전체 머신 에뮬레이터(v86, JSLinux, container2wasm, QEMU의 wasm 빌드) | Linux, 에뮬레이션 | 수정 없음, 에뮬레이션 | 에뮬레이션 |
| 시스템 콜 에뮬레이터 | 없음(런타임이 시스템 콜 재구현) | 수정 없음, 에뮬레이션 | 런타임 자체 |
| wasm용 POSIX 런타임(Wasmer WASIX, WebContainers, BrowserPod) | 없음(런타임이 시스템 콜 제공) | wasm용 재빌드 또는 JavaScript | 없음 |
| MMU 없는 Linux(linux-wasm, tombl/linux, WasmLinux(LKL)) | Linux, wasm 네이티브 | wasm용 재빌드 | 없음 |
| **unkernel** | **Linux, wasm 네이티브** | **수정 없는 aarch64, 에뮬레이션** | **실제 페이지 테이블** |

커널은 WebAssembly로 직접 컴파일됩니다. 사용자 프로그램은 **kwemu** 위에서 실행됩니다. kwemu는 Zig로 작성돼 커널에 연결된 aarch64 CPU입니다. kwemu는 커널 자신의 페이지 테이블을 순회하므로 메모리 관리는 실제 Linux 코드가 수행합니다.

프로그램이 시스템 콜을 내면 kwemu가 커널로 돌아가고, 커널은 wasm 네이티브로 처리합니다. 중간에 에뮬레이션된 trap이나 커널 모드가 없습니다. 태스크 전환은 JSPI(`WebAssembly.Suspending`)를 사용하므로 커널은 일시 정지·재개할 수 있는 실제 스택을 갖습니다.

kwemu는 게스트 코드 블록을 한 번 디코딩해 간결한 연산으로 실행하고(연산이 없는 것은 참조 인터프리터가 처리), 자주 실행되는 사용자 코드는 2단계 JIT를 거칩니다. JIT는 실행 중에 해당 블록을 wasm 모듈로 컴파일하며 결과가 인터프리터와 비트 단위로 일치합니다. 각 단계의 비용은 [벤치마크](#-벤치마크)에 나옵니다.

장치는 JavaScript 호스트와 통신하는 작은 준가상화 드라이버입니다: [블록](#디스크-추가)(kwblk), [네트워크](#네트워크-추가)(kwnet, JS의 사용자 모드 TCP/IP 스택 포함), [화면·입력·사운드](#화면-입력-사운드)(kwfb, kwinput, kwsnd), [vsock](#vsock으로-통신하기)(kwvsock), [공유 메모리](#공유-메모리)(kwshm).

### 📊 벤치마크

이 설계는 시스템 콜에서 가장 큰 이점을 줍니다. 아래는 Node에서 측정했습니다.

<p align="center">
  <img alt="네이티브, qemu-user, qemu-system, unkernel의 연산당 시간: getppid 110, 320, 1662, 172 ns; /dev/zero에서 64 B read 161, 481, 2247, 172 ns; 파이프 write+read 417, 1032, 7256, 482 ns; fork+exit+wait 73, 537, 1178, 57 µs" src="assets/performance.svg" width="760">
</p>

이 테스트(2026-11-14)에서는 fork가 네이티브보다 빠릅니다. 순수 연산은 느립니다. kwemu의 디코딩 연산 인터프리터는 Node에서 정수 코드를 초당 약 2.5~3억 게스트 명령으로 실행하고(2026-11-17), JIT는 실제 Alpine 작업을 그보다 1.6~2.3배 빠르게 만듭니다(2026-11-18: ash 루프 2.5 s 대 4.0 s, `seq 100000 | sort -r` 3.1 s 대 7.1 s, `seq 250000 | gzip | gunzip` 3.5 s 대 6.5 s). 여전히 네이티브보다는 크게 느립니다.

### 🚧 알려진 한계

- SDK와 CLI는 기본적으로 CPU 1개로 부팅하고, 페이지는 가능한 곳에서 여러 개로 부팅합니다(`?cpus=`). 여러 CPU의 스냅샷(SMP), 즉 페이지에서 일시 정지된 세션은 같은 수의 CPU에서만 다시 시작됩니다.
- IPv6 없음, DHCP와 DNS 외의 UDP 없음, 외부에서 들어오는 연결 없음([`vm.connect()`, `vm.fetch()`](#vsock으로-통신하기)와 `--forward`는 vsock으로 게스트 서버에 연결).
- 하드웨어 브레이크포인트·워치포인트 없음. `gdb`의 워치포인트는 프로그램을 한 단계씩 실행하는 소프트웨어 방식입니다.
- 몇 번 실행되지 않는 코드(큰 프로그램의 시작 부분, 예: `npm`)는 인터프리터에 남고, FP와 AdvSIMD 부동소수점은 JIT 코드 안에서도 인터프리터를 거칩니다. 호스트 엔진에 wasm SIMD가 없으면 OpenSSL의 AES와 SHA 경로도 인터프리터에서 실행됩니다.
- 커널의 wasm trap은 세션을 종료합니다.

## 🧩 JavaScript에서 사용하기

```sh
npm install unkernel
```

```js
import { createKernel, fetchDistro } from "unkernel";

const vm = await createKernel({ distro: await fetchDistro("alpine") });   // Alpine, 네트워크 없음
vm.onOutput((bytes) => process.stdout.write(bytes));
vm.write("uname -a; poweroff\n");

const { code, kind } = await vm.exited;          // 0, "halt"
```

`unkernel`을 import하면 Node 또는 브라우저 엔트리가 자동으로 선택되고, `unkernel/node`나 `unkernel/web`으로 명시적으로 고를 수도 있습니다. 커널은 패키지에 포함(`unkernel/unkernel.wasm`)되고 엔트리 옆에서 읽히며, 다운로드하면서 스트리밍·컴파일됩니다. 작은 기본 시스템이 함께 들어 있어 배포판 이미지를 overlay 루트 아래 읽기 전용으로 마운트하고 init을 실행합니다. `distro` 없이 `createKernel()`를 호출하면 다운로드가 필요 없는 기본 셸(busybox와 unkernel 도구)이 부팅됩니다.

배포판 이미지는 패키지에 없습니다. Node에서 `fetchDistro("alpine")`(또는 `"debian"`)는 패키지 버전의 GitHub 릴리스에서 한 번 내려받고, 릴리스의 `distros.json`(크기와 SHA-256)으로 검증한 뒤 `~/.cache/unkernel`(`UNKERNEL_CACHE_DIR`)에 보관하고 경로를 반환합니다. SDK의 다른 부분은 아무것도 다운로드하지 않습니다. 브라우저에서는 이미지를 직접 호스팅하고(range 요청으로 지연 로드) URL을 넘깁니다:

```js
const vm = await createKernel({ distro: "/distros/alpine.erofs" });
```

루트 파일 시스템 변경은 메모리에 남지만, 영속 데이터 디스크(`kwdata`)를 붙이면 배포판별로 그 디스크의 `/data/distros/<name>/`에 저장됩니다.

### 네트워크 추가

```js
import { createKernel, directBackend, wispBackend, DEFAULT_WISP_SERVERS } from "unkernel";

await createKernel({ net: directBackend() });                       // Node: 호스트 소켓
await createKernel({ net: wispBackend(DEFAULT_WISP_SERVERS) });     // 어디서든: Wisp 프록시
```

`net`을 넘기지 않으면 네트워크는 꺼져 있습니다. `connect`와 `lookup` 메서드를 가진 객체라면 게스트의 TCP와 DNS를 전달할 수 있으므로 자체 백엔드를 만들 수 있습니다.

### 디스크 추가

```js
import { createImageFromKwsparse, createKernel, bundledBoot, openDisk } from "unkernel/node";

const vm = await createKernel({
  distro,
  disks: [await openDisk("data.img")],           // 데이터 디스크, 또는 임의의 ext4 이미지/https:// URL
});
```

`createImageFromKwsparse(file, template)`는 커널이 담고 있는 템플릿(`bundledBoot(module).datadisk`)으로 새 데이터 디스크를 만듭니다. 브라우저에서는 `openHttpDisk(url)`이 쓰기를 IndexedDB에 보관하고, `openDataDisk()`은 [페이지](#-브라우저에서-사용하기)가 쓰는 영속 데이터 디스크를 제공합니다. `BlockDevice`를 구현한 것이라면 무엇이든 되고, 자기 디스크를 루트로 쓸 수도 있습니다: `cmdline: "console=hvc0 root=/dev/wda rw"`에 `initrd: null`.

### 콘솔과 수명 주기

```js
// vm.output: ReadableStream. 부팅 이후의 모든 출력과 이후 실시간 출력
vm.output.pipeTo(new WritableStream({ write: (b) => process.stdout.write(b) }));
vm.write("ls /\n");                              // 또는 WritableStream인 vm.input에 쓰기
vm.resize(120, 40);                              // 포그라운드 프로그램이 SIGWINCH를 받음

await vm.sync();                                 // 게스트 디스크 플러시
console.log(vm.stats());                         // 메모리, 디스크, 네트워크, JIT 카운터
const { code, reason, kind } = await vm.exited;  // stop()은 즉시 정지
```

### 프로그램 실행

```js
const { stdout, exitCode } = await vm.exec("uname", ["-a"]);
const { stdout: sum } = await vm.exec("sha256sum", [], { input: "hello" });
```

`exec()`는 파이프 위에서 프로그램을 실행하고 `{ stdout, stderr, exitCode, signal }`로 해결되며, 0이 아닌 종료 코드도 마찬가지입니다. 바이트가 필요하면 `encoding: "buffer"`를, `cwd`나 `env`는 `child_process`에 넘기듯 넘기세요. 배포판 이미지에서 프로그램은 `user` 사용자(uid 1000, `/home/user`)로 실행되고 비밀번호 없이 `sudo`를 쓸 수 있습니다. `user: "root"`(또는 다른 이름이나 uid)로 다른 사용자로 실행할 수 있습니다. 기본 셸은 root입니다.

```js
const sh = await vm.spawn();                     // 자기 pty의 로그인 셸
sh.output.pipeTo(new WritableStream({ write: (b) => process.stdout.write(b) }));
await sh.write("cat /etc/alpine-release; exit\n");
console.log(await sh.ended);                     // { type: "exit", code: 0 }
```

`spawn(file, args, { cols, rows })`는 zigpty/node-pty 형태로 pty에서 프로그램을 실행하며 `resize()`, `kill(signal)`, `close()`(hangup)를 제공합니다. 원하는 만큼 실행할 수 있습니다. `output`을 계속 읽으세요. 읽는 사람이 없으면 게스트 프로그램이 기다립니다.

```js
const gz = await vm.spawn("gzip", ["-c"], { pty: false });
gz.stderr.cancel();                              // 두 출력을 읽거나 하나를 취소
const zipped = new Response(gz.stdout).bytes();
await new Response("hello\n").body.pipeTo(gz.stdin);   // 그다음 EOF
console.log((await zipped).length);
```

`pty: false`에서는 `stdin`, `stdout`, `stderr` 웹 스트림이 바이트 단위로 연결됩니다.

### 호스트 파일 마운트

```js
import { createKernel, MemoryFs, nodeFs } from "unkernel";

const mem = new MemoryFs();
mem.onChange((c) => console.log(c.type, c.path));   // 게스트가 무엇을 바꿨는지

const vm = await createKernel({
  mounts: {
    "/mnt/host": { "hello.txt": "hi", dir: { "a.bin": bytes }, "now.txt": () => Date() },
    "/mnt/mem": mem,
  },
});
await vm.exec("cp", ["/etc/os-release", "/mnt/mem/"]);
console.log(mem.readText("/os-release"));

const work = await vm.mount("/work", nodeFs("."), { readOnly: true });   // Node 전용
await work.unmount();
```

파일 시스템은 일반 객체 트리(함수는 열 때마다 한 번 계산되는 파일), 호스트에서 읽고 쓰는 `MemoryFs`, `nodeFs(dir)`, 또는 자체 `Fs`입니다. `Fs`는 경로별 `getattr`, `readdir`, `open`(동기·비동기)와 원하는 변경 메서드를 구현하면 됩니다. 마운트는 vsock 위 9p로 제공됩니다. 게스트의 모든 쓰기는 즉시 호스트에 전달되고, 호스트의 변경은 1초 안에 게스트에 반영됩니다.

### vsock으로 통신하기

```js
const listener = vm.vsock.listen(5000);          // 게스트 프로그램은 CID 2, 포트 5000에 연결
vm.write("echo hello | kwbox vsock connect 5000\n");
const conn = await listener.accept();
console.log(await new Response(conn.readable).text());   // "hello\n"
conn.close();

const c = await vm.vsock.connect(6000);          // 포트 6000에서 대기하는 게스트 프로그램
await c.writable.getWriter().write("ping");
```

이것은 실제 흐름 제어가 있는 바이트 스트림이며 중간에 네트워크가 없습니다. `vsock: false`를 넘기지 않으면 vsock이 켜져 있습니다.

```js
const sock = await vm.connect(8000);             // 게스트의 127.0.0.1:8000으로 TCP
await new Response("hello\n").body.pipeTo(sock.writable);   // 그다음 EOF(하프 클로즈)
console.log(await new Response(sock.readable).text());
```

`vm.connect(port)`는 게스트의 kwtty를 통해, vsock으로 게스트 루프백의 TCP 서버에 연결하므로 네트워크가 필요 없습니다. 게스트가 연결되면(아무것도 대기하지 않으면 `PtyError` `ECONNREFUSED`) `readable`, `writable` 바이트 스트림, 하프 클로즈, `close()`, `closed`와 함께 해결됩니다. [CLI](#-터미널에서-실행하기)의 `--forward HOSTPORT:GUESTPORT`가 이를 사용합니다.

`vm.fetch(url, init)`는 게스트의 서버로 HTTP/1.1 요청을 보내고 본문이 스트리밍되는 `Response`를 반환합니다. 항상 URL 포트의 게스트 127.0.0.1에 연결하고 호스트명은 `Host` 헤더에만 들어가므로, `vm.fetch("http://localhost:8000/")`는 8000 포트의 개발 서버에 닿습니다. `fetchOver(connect, url, init)`은 임의의 바이트 스트림 위에서 같은 클라이언트를 사용합니다.

### 공유 메모리

```js
const vm = await createKernel({ shm: true });
await vm.exec("sh", ["-c", "printf result > /dev/shm/output"]);

const output = await vm.shm.open("output");      // 게스트 프로그램이 만든 파일
const data = await output.read();
const views = output.views();                    // 제로카피. 커널이 다시 실행될 때까지 유효

const input = await vm.shm.create("input", 1 << 20);   // 게스트의 /dev/shm/input
await input.write(0, bytes);
```

게스트 init이 `/dev/shm`을 마운트한 뒤에 존재하므로, `create()` 전에 게스트를 기다리세요(`exec()`는 기다립니다). `openId(id)`는 게스트 프로그램이 `/dev/kwshm`으로 내보낸 memfd를 엽니다. `views()`와 `readSync()`는 `vm.shm.inPlace`가 true인 곳에서 동작합니다. 인라인, 그리고 공유 메모리와 여러 CPU를 쓰는 워커 모드(cross-origin isolated 페이지, Node); 그 외에는 `read()`가 커널의 워커로 넘어갑니다.

### 화면, 입력, 사운드

```js
import { createKernel, domCodeToLinux, pcmToFloat32 } from "unkernel";

const vm = await createKernel({
  display: { width: 800, height: 600 },          // 게스트에 /dev/fb0이 생김
  onDisplay: (mode) => console.log(mode),        // 프로그램이 열었으면 그 모드, 닫았으면 null
  sound: { onChunk: ({ data, format }) => play(pcmToFloat32(data, format)) },
});

const frame = vm.frame();                        // RGBA, 아무것도 그리지 않으면 null
if (frame) ctx.putImageData(new ImageData(frame.data, frame.width, frame.height), 0, 0);

addEventListener("keydown", (e) => {
  const key = domCodeToLinux(e.code);
  if (key && vm.evdev.keyboardOpen) vm.evdev.key(key, true);
});
```

`evdev`에는 마우스·태블릿용 `button()`, `move()`, `moveTo()`, `wheel()`도 있습니다. `onInput`은 프로그램이 키보드와 마우스를 열 때 알려줍니다. 그 전에는 콘솔로 키를 보내세요. `readFrame()`는 새로운 프레임을 기다립니다.

브라우저에서는 `createAudioOut()`이 Web Audio로 게스트 사운드를 재생합니다:

```js
import { createAudioOut, createKernel } from "unkernel/web";

button.hidden = true;
const audio = createAudioOut({
  onChange: (state) => { button.hidden = state !== "waiting"; },  // "클릭하여 재생"
});
const vm = await createKernel({ sound: audio });
button.onclick = () => audio.resume();           // 또는 페이지의 다른 클릭/키 입력
```

브라우저는 페이지에서 클릭·탭·키 입력이 있어야 사운드를 시작합니다. 그 전에는 게스트가 재생한 최근 `holdSeconds`(10)초를 보관합니다. 그때까지 끝난 클립은 전체가 재생되고, 스트림은 라이브로 이어집니다. `audio.muted = true`로 음소거할 수 있습니다. 하나의 싱크는 한 번에 하나의 커널만 담당하며 커널보다 오래 살아남습니다. 다음 커널에 넘기거나 `close()`하세요.

### 게스트의 GL (브라우저)

```js
const vm = await createKernel({ distro: "/distros/debian.erofs", gl: true });
await vm.gl.ready;                               // 게스트가 연결됨. 렌더러는 첫 GL 사용 시 로드
await vm.exec("sudo", ["apt-get", "install", "-y", "mesa-utils", "libegl-mesa0", "libgles2"]);
const r = await vm.exec("sh", ["-c", "GALLIUM_DRIVER=virpipe LIBGL_ALWAYS_SOFTWARE=1 eglinfo -B -p surfaceless"]);
```

게스트의 Mesa(Debian, `virpipe` 드라이버)가 wasm으로 컴파일된 virglrenderer(`virgl.wasm`)를 통해 페이지의 WebGL2 컨텍스트에 그리고, 프레임을 readback으로 받습니다. GL 2.1과 GLES 3.0을 지원하며 surfaceless 또는 Xvfb 아래에서 동작합니다. Node에는 WebGL이 없어 `gl`은 로그 한 줄과 함께 무시됩니다.

`gpu: true`도 함께 켜면(kwvirtio가 있는 커널 필요) 게스트가 같은 렌더러로 3D가 되는 virtio-gpu 장치를 받습니다. 기본 Mesa가 `/dev/dri/renderD128`과 `card0`(드라이버 `virtio_gpu`)을 찾아 환경 변수 없이 그를 통해 렌더링하고, KMS 클라이언트(kmscube, `glmark2-es2-drm`, Wayland 컴포지터)의 프레임은 렌더러의 텍스처에서 나옵니다:

```js
const vm = await createKernel({ distro, gl: true, gpu: true, display: { width: 1280, height: 720 } });
// 애니메이션 프레임마다: 스캔아웃의 최신 프레임, readback 없음(null: 그 위에 GL 클라이언트 없음)
if (vm.gl.gpu.drawFrame(ctx) === null) { /* 위처럼 vm.frame() 표시 */ }
// 창 크기가 바뀜: 새 선호 모드로 hotplug, KMS 클라이언트가 반영할 수 있음
vm.updateDisplaySize({ width: 1600, height: 900 });
```

### 게스트의 Vulkan (WebGPU 지원 브라우저)

```js
const vm = await createKernel({ distro: "/distros/debian.erofs", vk: true });
await vm.exec("sudo", ["apt-get", "install", "-y", "libvulkan1", "vulkan-tools"]);
const r = await vm.exec("vulkaninfo", ["--summary"]);   // deviceName = kwvk (WebGPU)
```

기본 시스템에는 Vulkan 드라이버(Vulkan 로더가 스스로 찾는 ICD)가 들어 있어 게스트의 Vulkan 호출을 페이지의 WebGPU 장치 위 렌더러로 보냅니다. SPIR-V 셰이더는 `kwvk-naga.wasm`을 거쳐 WGSL이 됩니다. 게스트가 처음 Vulkan 프로그램을 실행하기 전에는 아무것도 로드되지 않습니다(`vm.vk.status`). Wayland, X11, headless 프레젠테이션을 갖춘 Vulkan 1.2(프레임은 readback)를 지원하고 vkcube, vkmark, SDL의 GPU API, GTK 4의 Vulkan 렌더러가 동작합니다. Node에는 WebGPU가 없어 `vk`는 로그와 함께 무시됩니다. 설계는 [vk/PROTOCOL.md](vk/PROTOCOL.md)에 있습니다.

### 워커에서 실행하기

```js
const vm = await createKernel({
  worker: true,
  distro,                                        // 경로 또는 URL
  net: { kind: "net", backend: { kind: "direct" } },
  disks: [{ kind: "file", path: "data.img" }],
});
```

커널은 워커 스레드 또는 Web Worker에서 같은 API로 실행됩니다. 디스크와 네트워크는 워커가 만드는 명세로 넘깁니다: Node에서는 `{ kind: "file", path }`, 브라우저에서는 `{ kind: "http", url }`과 `{ kind: "data", template: "bundled" }`. 가능하면 입력과 프레임은 공유 메모리를 거칩니다(`vm.transport`가 알려줌). 이 모드는 실험적입니다.

SMP 커널(SMP 패치가 든 번들)은 `cpus: 4`로 여러 CPU에서 부팅되며, 각 CPU는 하나의 공유 메모리 위 자기 스레드에서 실행됩니다. 브라우저에서는 cross-origin isolated 페이지와 `worker: true`가 필요합니다. 한 CPU가 다른 CPU를 기다리는 동안 블록되기 때문에 페이지의 메인 스레드는 그렇게 할 수 없기 때문입니다. `webCpuBlocker()`가 이유를, `vm.stats().cpus`가 커널이 받은 CPU 수를 알려줍니다.

서버에서는 `worker: true`가 속도 손실 없이 이벤트 루프를 자유롭게 유지하고, `cpus: 4`가 추가 CPU의 이점을 대부분 줍니다(병렬 작업에서 약 3배; 8이나 16은 별로 차이가 없고, CPU마다 부팅 시간이 늘고 게스트 메모리 9 MiB를 차지합니다). `node test/profile.ts`가 호스트를, 페이지의 `/profile.html`이 브라우저를 측정합니다.

### 부팅 옵션과 헬퍼

```js
import { checkSupport, ConsoleRouter, createKernel } from "unkernel";

const support = await checkSupport();            // 부팅 전에 JSPI 등 확인
if (!support.ok) throw new Error(support.problems.join("\n"));

const vm = await createKernel({
  kernel: "./my-kernel.wasm",                    // URL, 바이트, Response 또는 WebAssembly.Module
  initrd: "./initramfs.cpio.gz",                 // null: 없음
  cmdline: "console=hvc0 rdinit=/init",
  memoryMiB: 1024,
  jit: false,                                    // 인터프리터만
  onProgress: (p) => console.log(p.stage),
});

const router = new ConsoleRouter({               // 프로그램 출력과 구분되는 커널 로그 줄
  onKernelLine: (line, { important }) => important && console.warn(line),
  onUserOutput: (text) => process.stdout.write(text),
});
vm.onOutput((bytes) => router.write(bytes));
```

커널의 [알려진 한계](#-알려진-한계) 외에 SDK에도 한계가 있습니다. 터미널 세션 외의 게스트 에이전트는 없으므로 터미널이나 콘솔, 또는 자기 프로그램으로 vsock을 통해 게스트를 제어합니다. `stop()`은 게스트를 깔끔하게 종료하지 않으므로 `poweroff`를 권장합니다. 스레드당 커널 하나만 실행할 수 있습니다. 타입은 `.d.mts`로 배포되고 DOM의 `WebAssembly` 타입을 사용하므로 Node 전용 TypeScript 프로젝트는 `"lib": ["dom"]`이나 `skipLibCheck`가 필요합니다.

## 🛠️ 소스에서 빌드하기

Linux(x86-64 또는 arm64), Zig 0.16, Node 24, wasm 타깃이 있는 clang 21+와 일반 빌드 도구가 필요합니다. `./setup.sh --check`가 빠진 것을 알려줍니다. 첫 빌드는 약 12분 걸리고 대부분 패치된 `wasm-ld`에 쓰이며 디스크 5 GiB를 사용합니다.

```sh
./setup.sh              # 확인한 뒤 전체 빌드
node js/cli.ts          # 빌드한 것 부팅(Alpine은 vendor/build/distro/에서)
pnpm install && pnpm dev   # http://localhost:8080의 웹 페이지
zig build test          # 에뮬레이터 테스트
```

빌드가 만드는 것은 커널 번들 `vendor/build/bundle/unkernel.wasm`과 배포판 이미지 `vendor/build/distro/{alpine,debian}.erofs`(색인 `distros.json`)입니다. 소스 체크아웃은 이를 사용하며 다운로드하지 않습니다. [guest/README.md](guest/README.md)가 기본 시스템과 배포판 추가 방법을 설명합니다.

[kernel/README.md](kernel/README.md)는 커널 디렉터리와 빌드 단계를 정리합니다. [AGENTS.md](AGENTS.md)와 [.agents/](.agents/)에는 기여자 노트(커널, 장치, 게스트 이미지, 불변식, 워크플로, 실행할 테스트, [로드맵](.agents/status.md))이 있습니다.

## 🙏 감사의 글

♥를 담아 [Pooya Parsa](https://x.com/_pi0_) ([pi0](https://github.com/pi0))가 만들었고, [▲ Vercel](https://vercel.com/open-source-program)이 후원했습니다.

감사합니다:

- [Kernarium](https://github.com/imxieyi/Kernarium): 소프트웨어 MMU 뒤에 에뮬레이션된 사용자 공간을 둔 네이티브 커널이라는 아이디어를 주었습니다.
- Joel Severin의 [linux-wasm](https://github.com/joelseverin/linux-wasm): 이 커널이 자란 `arch/wasm` 포트, wasm-ld 링커 스크립트 패치, Kbuild 툴체인 래퍼.
- [iSH](https://github.com/ish-app/ish)와 [v86](https://github.com/copy/v86): 빠른 사용자 모드 에뮬레이터와 wasm JIT을 만드는 법을 보여주었습니다.
- [virglrenderer](https://gitlab.freedesktop.org/virgl/virglrenderer)와 [Mesa](https://mesa3d.org/): 게스트 GL — 게스트의 Mesa virgl 드라이버와, [Emscripten](https://emscripten.org/)으로 wasm 컴파일해 페이지 WebGL2에 그리는 virglrenderer.
- [Alpine Linux](https://alpinelinux.org/)와 [Debian](https://www.debian.org/): 부팅되는 배포판. [erofs-utils](https://git.kernel.org/pub/scm/linux/kernel/git/xiang/erofs-utils.git), [LZ4](https://github.com/lz4/lz4), [Zstandard](https://github.com/facebook/zstd)로 패키징.
- [wland](https://github.com/pithings/wland): 게스트 창을 페이지로 가져오는 Wayland 컴포지터. [wterm](https://wterm.dev/): 페이지의 터미널.
- [Zig](https://ziglang.org/), [LLVM](https://llvm.org/), [Binaryen](https://github.com/WebAssembly/binaryen): 빌드 도구. [React](https://react.dev/), [Tailwind CSS](https://tailwindcss.com/), [Vite](https://vite.dev/), [Nitro](https://nitro.build/), [Geist](https://vercel.com/font) 글꼴: 페이지 구성.
- [Wisp](https://github.com/MercuryWorkshop/wisp-protocol): 브라우저에서 게스트 네트워크 뒤의 프로토콜.

## 📄 라이선스

모두 오픈 소스입니다: 커널 패치, 에뮬레이터와 JIT, 패치된 링커, SDK, 페이지. `./setup.sh`가 커널 파일을 소스에서 다시 빌드합니다.

파일에서 따로 명시하지 않는 한 프로젝트는 GPL-2.0-or-later입니다([LICENSE](LICENSE)). JavaScript SDK와 페이지(`js/`, `web/`, SDK 테스트)는 MIT([LICENSE-MIT](LICENSE-MIT))이므로 어디에나 내장할 수 있습니다.

npm 패키지는 Linux 커널(GPL-2.0)과 작은 기본 시스템(Alpine의 정적 busybox, GPL-2.0, unkernel 자체 도구)을 담으므로 `MIT AND GPL-2.0-only`입니다. 게스트 GL 렌더러(`virgl.wasm`: virglrenderer와 Emscripten 런타임은 MIT, unkernel 접착 코드는 GPL-2.0-or-later)와 게스트 Vulkan 변환기(`kwvk-naga.wasm`: naga와 Rust 의존성은 MIT 또는 Apache-2.0, unkernel 접착 코드는 GPL-2.0-or-later)도 함께 들어 있습니다. 패키지와 페이지의 `/licenses.md`에 있는 [THIRD-PARTY.md](THIRD-PARTY.md)가 unkernel 것이 아닌 것과 그 라이선스가 요구하는 고지를 정리합니다. 내려받는 배포판 이미지는 배포판 패키지를 담고 각자의 라이선스를 따릅니다. 커널 소스는 Linux 7.3.4 + [kernel/patches/linux](kernel/patches/linux)입니다(`arch/wasm`은 linux-wasm 기반). 그 패치와 `kernel/tools/fake-llvm`은 GPL-2.0-only이고, `kernel/patches/llvm`의 패치는 LLVM 라이선스(Apache-2.0 WITH LLVM-exception)를 따릅니다.
