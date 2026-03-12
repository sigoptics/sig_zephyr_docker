#docker build --build-arg ZEPHYR_VERSION=v3.7.0 -t lukecorb/sig_zephyr:v3.7.0 .

docker build --build-arg ZEPHYR_VERSION=v3.7.0 --build-arg ZEPHYR_SDK_VERSION=0.17.4 -t lukecorb/sig_zephyr:v3.7.0 .
