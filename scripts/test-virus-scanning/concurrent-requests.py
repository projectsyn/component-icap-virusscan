#!/usr/bin/env python3

import argparse
import asyncio
import aiohttp
import time
import sys
import os
from dataclasses import dataclass
from typing import List, Dict
import statistics


@dataclass
class RequestResult:
    """Result of a single request"""
    url: str
    status: int
    duration: float
    success: bool
    error: str = ""


@dataclass
class TestSummary:
    """Summary of the entire test run"""
    total_requests: int
    successful: int
    failed: int
    duration: float
    requests_per_second: float
    avg_response_time: float
    min_response_time: float
    max_response_time: float
    median_response_time: float
    p95_response_time: float
    p99_response_time: float


class StressTestRunner:
    def __init__(self, test_url: str, concurrency: int):
        self.test_url = test_url
        self.concurrency = concurrency
        self.results: List[RequestResult] = []
        self.lock = asyncio.Lock()

    async def make_request(self, session: aiohttp.ClientSession,
                           file_path: str = None) -> RequestResult:
        """Make a single request"""
        start_time = time.time()

        try:
            # If file_path is provided, upload it
            if file_path and os.path.exists(file_path):
                with open(file_path, 'rb') as f:
                    data = f.read()
                async with session.post(self.test_url, data=data) as response:
                    status = response.status
                    await response.read()
            else:
                async with session.get(self.test_url) as response:
                    status = response.status
                    await response.read()

            duration = time.time() - start_time

            success = False
            if file_path and "eicar" in file_path and status == 403:
                success = True

            if (not file_path or not "eicar" in file_path) and status < 400:
                success = True

            return RequestResult(
                url=self.test_url,
                status=status,
                duration=duration,
                success=success
            )

        except asyncio.TimeoutError:
            duration = time.time() - start_time
            return RequestResult(
                url=self.test_url,
                status=0,
                duration=duration,
                success=False,
                error="Timeout"
            )
        except Exception as e:
            duration = time.time() - start_time
            return RequestResult(
                url=self.test_url,
                status=0,
                duration=duration,
                success=False,
                error=f"{type(e).__name__}: {str(e)}"
            )

    async def worker(self, worker_id: int, queue: asyncio.Queue,
                     session: aiohttp.ClientSession, file_path: str = None):
        """Worker that processes requests from queue"""
        processed = 0
        while True:
            try:
                item = queue.get_nowait()
                processed += 1
            except asyncio.QueueEmpty:
                break
            except Exception as e:
                print(f"Worker {worker_id} error getting from queue: {e}")
                break

            try:
                result = await self.make_request(session, file_path)
                async with self.lock:
                    self.results.append(result)
            except Exception as e:
                print(f"Worker {worker_id} error making request: {e}")
            finally:
                queue.task_done()

    async def run_requests(self, num_requests: int, file_path: str = None):
        """Run the stress test with specified number of requests"""
        print(f"Setting up test: {num_requests} requests with {self.concurrency} workers")

        queue = asyncio.Queue()

        for i in range(num_requests):
            await queue.put(i)

        print(f"Queue filled with {queue.qsize()} items")

        timeout = aiohttp.ClientTimeout(total=30)

        connector = aiohttp.TCPConnector(
            limit=self.concurrency * 2,
            limit_per_host=self.concurrency,
            force_close=True
        )

        print(f"Creating session...")
        async with aiohttp.ClientSession(
                connector=connector,
                timeout=timeout,
        ) as session:
            print("Session created, starting workers...")

            workers = [
                asyncio.create_task(self.worker(i, queue, session, file_path))
                for i in range(self.concurrency)
            ]

            print(f"Created {len(workers)} workers, waiting for completion...")

            await asyncio.gather(*workers)

            print(f"All workers done. Processed {len(self.results)} results.")

    def calculate_summary(self, test_duration: float) -> TestSummary:
        """Calculate test summary statistics"""
        if not self.results:
            return TestSummary(
                total_requests=0,
                successful=0,
                failed=0,
                duration=test_duration,
                requests_per_second=0,
                avg_response_time=0,
                min_response_time=0,
                max_response_time=0,
                median_response_time=0,
                p95_response_time=0,
                p99_response_time=0,
            )

        durations = [r.duration for r in self.results]
        successful = sum(1 for r in self.results if r.success)
        failed = len(self.results) - successful

        durations.sort()

        return TestSummary(
            total_requests=len(self.results),
            successful=successful,
            failed=failed,
            duration=test_duration,
            requests_per_second=len(self.results) / test_duration if test_duration > 0 else 0,
            avg_response_time=statistics.mean(durations) if durations else 0,
            min_response_time=min(durations) if durations else 0,
            max_response_time=max(durations) if durations else 0,
            median_response_time=statistics.median(durations) if durations else 0,
            p95_response_time=durations[int(len(durations) * 0.95)] if durations else 0,
            p99_response_time=durations[int(len(durations) * 0.99)] if durations else 0,
        )

    def print_summary(self, summary: TestSummary):
        """Print test summary"""
        print("\n" + "=" * 60)
        print("STRESS TEST SUMMARY")
        print("=" * 60)
        print(f"Total Requests:    {summary.total_requests}")
        print(f"Successful:        {summary.successful} ({summary.successful / summary.total_requests * 100:.1f}%)")
        print(f"Failed:            {summary.failed} ({summary.failed / summary.total_requests * 100:.1f}%)")
        print(f"Duration:          {summary.duration:.2f} seconds")
        print(f"Requests/sec:      {summary.requests_per_second:.2f}")
        print("-" * 60)
        print(f"Avg Response Time: {summary.avg_response_time * 1000:.2f} ms")
        print(f"Min Response Time: {summary.min_response_time * 1000:.2f} ms")
        print(f"Max Response Time: {summary.max_response_time * 1000:.2f} ms")
        print(f"Median Response:   {summary.median_response_time * 1000:.2f} ms")
        print(f"P95 Response:      {summary.p95_response_time * 1000:.2f} ms")
        print(f"P99 Response:      {summary.p99_response_time * 1000:.2f} ms")
        print("=" * 60)

        if summary.failed > 0:
            print("\nERROR BREAKDOWN:")
            error_counts: Dict[str, int] = {}
            for r in self.results:
                if not r.success:
                    error = r.error if r.error else f"HTTP {r.status}"
                    error_counts[error] = error_counts.get(error, 0) + 1
            for error, count in sorted(error_counts.items(), key=lambda x: x[1], reverse=True):
                print(f"  {error}: {count}")


def main():
    parser = argparse.ArgumentParser(
        description='Stress test a squid proxy with configurable concurrency'
    )
    parser.add_argument('--url', '-u',
                        default='http://localhost:3128',
                        help='Test URL to request (default: http://localhost:3128)')
    parser.add_argument('--concurrency', '-c',
                        type=int, default=10,
                        help='Number of concurrent requests (default: 10)')
    parser.add_argument('--requests', '-r',
                        type=int, default=100,
                        help='Total number of requests (default: 100)')
    parser.add_argument('--file', '-f',
                        default=None,
                        help='File to upload with each request')

    args = parser.parse_args()

    print(f"\nStarting stress test...")
    print(f"  Test URL:    {args.url}")
    print(f"  Concurrency: {args.concurrency}")
    print(f"  Requests:    {args.requests}")
    if args.file:
        print(f"  File:        {args.file}")
    print()

    runner = StressTestRunner(args.url, args.concurrency)

    start_time = time.time()
    asyncio.run(runner.run_requests(args.requests, args.file))
    test_duration = time.time() - start_time

    summary = runner.calculate_summary(test_duration)
    runner.print_summary(summary)

    if summary.total_requests > 0 and summary.failed > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()
