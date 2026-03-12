#docker build --build-arg ZEPHYR_VERSION=v3.7.1 -t lukecorb/sig_zephyr:v3.7.1 .

docker build --build-arg ZEPHYR_VERSION=v3.7.1 --build-arg ZEPHYR_SDK_VERSION=0.16.8 -t lukecorb/sig_zephyr:v3.7.1 .