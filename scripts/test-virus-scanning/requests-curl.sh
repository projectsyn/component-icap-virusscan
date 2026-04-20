#!/bin/bash

# Default values
URL="http://localhost:3128"
CONCURRENCY=10
REQUESTS=100
FILE_PATH=""

# Temporary file for results
RESULTS_FILE=$(mktemp)
trap "rm -f $RESULTS_FILE" EXIT

# Argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -u|--url) URL="$2"; shift ;;
        -c|--concurrency) CONCURRENCY="$2"; shift ;;
        -r|--requests) REQUESTS="$2"; shift ;;
        -f|--file) FILE_PATH="$2"; shift ;;
        -h|--help)
            echo "Usage: $0 [-u URL] [-c CONCURRENCY] [-r REQUESTS] [-f FILE]"
            echo "  -u, --url URL          Test URL (default: http://localhost:3128)"
            echo "  -c, --concurrency N    Number of concurrent requests (default: 10)"
            echo "  -r, --requests N       Total number of requests (default: 100)"
            echo "  -f, --file PATH        File to upload (POST request)"
            exit 0
            ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check file existence
if [[ -n "$FILE_PATH" && ! -f "$FILE_PATH" ]]; then
    echo "Error: File '$FILE_PATH' not found."
    exit 1
fi

# Function to execute a single request and output stats
# Format: "http_code time_total"
run_curl() {
    local url=$1
    local file=$2

    # Build curl command
    # -s: Silent
    # -o /dev/null: Discard body
    # -w "%{http_code} %{time_total}\n": Output format
    local cmd="curl -s -o /dev/null -w '%{http_code} %{time_total}\n'"

    if [[ -n "$file" ]]; then
        # POST request with file upload
        cmd="$cmd -X POST -T $file -H 'Content-Type: application/octet-stream' $url"
    else
        # GET request
        cmd="$cmd $url"
    fi

    # Execute and write to temp file
    # Since we run in parallel via xargs, we need to append to file safely
    eval $cmd >> $RESULTS_FILE
}

export -f run_curl
export URL
export FILE_PATH
export RESULTS_FILE

# Print setup info
echo -e "\nStarting stress test..."
echo "  Test URL:    $URL"
echo "  Concurrency: $CONCURRENCY"
echo "  Requests:    $REQUESTS"
if [[ -n "$FILE_PATH" ]]; then
    echo "  File:        $FILE_PATH"
fi
echo

# Start Timer
START_TIME=$(date +%s.%N)

# Run requests in parallel using xargs
# We generate a sequence of numbers to act as request IDs
# -P sets the concurrency (process pool size)
seq $REQUESTS | xargs -I {} -P $CONCURRENCY bash -c 'run_curl "$URL" "$FILE_PATH"'

# End Timer
END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc)

# Calculate and Print Summary
# We use awk to process the results file in one pass for stats
awk -v requests="$REQUESTS" \
    -v duration="$DURATION" \
    -v file="$FILE_PATH" \
    '
    BEGIN {
        success=0; failed=0;
        sum=0; min=99999999; max=0;
        count=0;
    }
    {
        status=$1;
        time=$2;

        # Collect data for calculations
        data[count] = time;
        sum += time;
        if (time < min) min = time;
        if (time > max) max = time;
        count++;

        # Determine success based on Python script logic
        is_success = 0;
        is_eicar = (file != "" && index(file, "eicar") > 0);

        if (is_eicar) {
            if (status == 403) is_success = 1;
        } else {
            if (status < 400) is_success = 1;
        }

        if (is_success) {
            success++;
        } else {
            failed++;
            # Track error counts
            err_key = "HTTP " status;
            if (status == "000") err_key = "Curl Error/Timeout";
            errors[err_key]++;
        }
    }
    END {
        if (count == 0) { print "No results recorded."; exit; }

        # Sort times for percentiles
        # Bubble sort is sufficient for typical test sizes in shell
        for (i=0; i<count; i++) {
            for (j=0; j<count-i-1; j++) {
                if (data[j] > data[j+1]) {
                    temp = data[j];
                    data[j] = data[j+1];
                    data[j+1] = temp;
                }
            }
        }

        avg = sum / count;
        rps = count / duration;

        # Calculate indices for percentiles
        # Python uses int(len * 0.95) which is effectively floor
        idx_median = int(count / 2);
        idx_p95 = int(count * 0.95);
        idx_p99 = int(count * 0.99);

        # Ensure indices are at least 1 (arrays are 0-indexed here)
        if (idx_median < 0) idx_median = 0;
        if (idx_p95 < 0) idx_p95 = 0;
        if (idx_p99 < 0) idx_p99 = 0;
        if (idx_p99 >= count) idx_p99 = count - 1;

        # Print Summary (mimicking Python print_summary format)
        print "\n============================================================";
        print "STRESS TEST SUMMARY";
        print "============================================================";
        printf "Total Requests:    %d\n", count;
        printf "Successful:        %d (%.1f%%)\n", success, (success/count*100);
        printf "Failed:            %d (%.1f%%)\n", failed, (failed/count*100);
        printf "Duration:          %.2f seconds\n", duration;
        printf "Requests/sec:      %.2f\n", rps;
        print "------------------------------------------------------------";
        printf "Avg Response Time: %.2f ms\n", avg * 1000;
        printf "Min Response Time: %.2f ms\n", min * 1000;
        printf "Max Response Time: %.2f ms\n", max * 1000;
        printf "Median Response:   %.2f ms\n", data[idx_median] * 1000;
        printf "P95 Response:      %.2f ms\n", data[idx_p95] * 1000;
        printf "P99 Response:      %.2f ms\n", data[idx_p99] * 1000;
        print "============================================================";

        if (failed > 0) {
            print "\nERROR BREAKDOWN:";
            for (k in errors) {
                printf "  %s: %d\n", k, errors[k];
            }
        }
    }
    ' "$RESULTS_FILE"
