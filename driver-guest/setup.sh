cd guest/guest-driver
make
sudo insmod coyote-guest.ko
echo 100 | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
cd 
