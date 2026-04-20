# Test virus scanning endpoint

This is a compose setup to test virus scanning.

## Run

Setup:

```shell
./test-files/generate-test-files.sh
```

```shell
# change this to the virus scanning endpoint
URL=https://httpbin.org/anything

./concurrent-requests.sh --url $URL --concurrency 3 --requests 10 --file test-files/medium-archive-with-eicar.zip
```
