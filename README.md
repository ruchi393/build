# OP-TEE build.git

This git contains makefiles etc to be able to build a full OP-TEE developer
setup for the OP-TEE project.

All official OP-TEE documentation has moved to http://optee.readthedocs.io. The
pages that used to be here in this git can be found under [build] and [Device
specific information] at he new location for the OP-TEE documentation.

// OP-TEE core maintainers

[build]: https://optee.readthedocs.io/en/latest/building/index.html
[Device specific information]: https://optee.readthedocs.io/en/latest/building/devices/index.html

# Build Instructions

Use normal repo and build setup for qemu_v8. Replace the following repos

1. Linux

https://git.linaro.org/people/alex.bennee/linux.git
Branch  - testing/virtio-rpmb

Config options to be enabled
CONFIG_RPMB=y
CONFIG_VIRTIO_RPMB=y
CONFIG_RPMB_INTF_DEV=y

2. QEMU 
For the vhost-rpmb backend, use following qemu

git@github.com:ruchi393/qemu.git
Branch - vhost-user-rpmb-fixes

This has fixes over original Alex Benne's qemu tree branch

git@github.com:stsquad/qemu.git
Branch - virtio/vhost-user-rpmb-v2

3. OPTEE-CLIENT

https://github.com/ruchi393/optee_client.git
Branch - virtio-rpmb

4. Build repo

https://github.com/ruchi393/build.git
Branch - virtio-rpmb

# Run Instructions

## On a terminal on host

Create a flash binary (flash.bin) of 16Mb - One time step

The "key" is the test key for RPMB also used by OP-TEE

```
cd \<repo\>/out/bin
dd if=/dev/zero of=flash.img bs=128k count=128
./vhost-user-rpmb --socket-path=vrpmb.sock --flash-path=flash.img  --verbose --debug --key-path=key --key-set
```

## On another terminal on host

```
cd build
make QEMU_VIRTFS_ENABLE=y -j 12 run
```

## From the terminal launched by QEMU running linux

```
# killall tee-supplicant
# tee-supplicant &
# xtest 1001
Test ID: 1001
Run test suite with level=0

TEE test application started over default TEE instance
######################################################
#
# regression
#
######################################################
 
* regression_1001 Core self tests
[    7.877687] virtio_rpmb virtio2: out = 1, in = 1
[    7.890038] virtio_rpmb virtio2: out = 1, in = 1
[    7.902755] virtio_rpmb virtio2: out = 2, in = 1
[    7.925756] virtio_rpmb virtio2: out = 1, in = 1
[    7.943407] virtio_rpmb virtio2: out = 1, in = 1
[    7.985777] virtio_rpmb virtio2: out = 1, in = 1
regression_1000.c:245: res has an unexpected value: 0xffff0000 = TEEC_ERROR_GENERIC, expected 0x0 = TEEC_SUCCESS
Segmentation fault

```

This will fail right now as virtio-rpmb supports read of only 1 block at a time while OP-TEE driver issues multiple block read.

To test the virtio interface, 
```
mkdir -p /host && mount -t 9p -o trans=virtio host /host; cd /host/linux/tools/rpmb
./rpmb -v get-info /dev/rpmb0
echo "get write counter"
./rpmb -v write-counter /dev/rpmb0 key
echo "generating data"
dd if=/dev/urandom of=data.in count=1 bs=256
echo "write data"
./rpmb -v write-blocks /dev/rpmb0 0 1 data.in key
echo "read data back"
./rpmb -v read-blocks /dev/rpmb0 0 1 data.out key
```
