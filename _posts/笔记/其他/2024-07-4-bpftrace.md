---
title: bpftrace
date: 2024-07-4
categories: [笔记, 无主题零碎]
tags: [网络]
---

# bpftrace

## bpftrace性能工具
![bpftrace_tools_early2019.png](/commons/其他/image/bpftrace_tools_early2019.png)

![bpftrace_internals_2018.png](/commons/其他/image/bpftrace_internals_2018.png)

BPFtrace 是一个高级的动态跟踪工具，用于 Linux 内核和用户态程序。它基于 eBPF（Extended Berkeley Packet Filter），提供了简单易用的脚本语言，允许用户编写复杂的监控和调试脚本，以获取系统和应用程序的运行时信息。

### 安装 BPFtrace：

可以通过包管理器安装，例如在 Ubuntu 上使用 sudo apt install bpftrace。

### 主要机制
kprobe、uprobe、tracepoint 和 perf_event 是 Linux 内核中用于性能分析和调试的四种主要机制。以下是它们的详细介绍和使用方法：

#### kprobe
kprobe 是一种动态插入内核探针的机制，用于监控内核函数的入口和出口。它可以帮助开发者调试和分析内核代码。

```
例子
# 跟踪每次调用 `do_sys_open` 内核函数时的文件名参数
sudo bpftrace -e 'kprobe:do_sys_open { printf("File opened: %s\n", str(arg1)); }'
# 仅跟踪特定进程的文件打开操作
sudo bpftrace -e 'kprobe:do_sys_open /pid == 1234/ { printf("File opened: %s\n", str(arg1)); }'
# 获取调用栈信息
sudo bpftrace -e 'kprobe:do_sys_open { @[kstack] = count(); }'
# 监控 do_sys_open 函数的调用
sudo bpftrace -e 'kprobe:do_sys_open { printf("do_sys_open called with filename: %s\n", str(arg1)); }'


```

#### uprobe
uprobe 是类似于 kprobe 的机制，但用于用户空间程序。它允许在用户空间应用程序的函数入口和出口处插入探针。

```
例子
# 监控用户态程序 `./myprogram` 中 `main` 函数的调用
sudo bpftrace -e 'uprobe:./myprogram:main { printf("main() called\n"); }'


```


#### tracepoint
tracepoint 是内核中预定义的跟踪点，可以在这些点插入钩子函数以收集数据。它们比 kprobe 和 uprobe 更稳定，因为它们是内核开发人员明确定义的。
> sudo bpftrace -l "tracepoint:*" 查看所有可用的 tracepoint

```
例子
# 统计每个系统调用的次数
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_* { @[probe] = count(); }'
# 统计不同 PID 的系统调用次数
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_* { @[pid] = count(); }'


```

#### perf_event
perf_event 是 Linux 内核中的性能监控框架，可以收集硬件性能计数器、软件事件、tracepoints、kprobes 和 uprobes 的数据。perf 工具是使用 perf_event 接口的用户空间应用。
* 手册 -> https://www.brendangregg.com/perf.html
> perf
记录 10 秒内的 CPU 活动
sudo perf record -a -g -- sleep 10
生成报告
sudo perf report

```
例子
记录 main 函数的活动:
sudo perf record -e cycles:u -a -g -p $(pgrep -n my_program)

```

#### 其他

```
组合
# 监控内核函数、用户空间函数和内核事件
sudo bpftrace -e '
kprobe:sys_execve { printf("execve called: %s\n", str(arg0)); }
uprobe:/usr/bin/bash:main { printf("bash main called\n"); }
tracepoint:tcp:tcp_connect { printf("TCP connect from %s to %s\n", ntop(args->saddr), ntop(args->daddr)); }
'
```

```
列出所有有 sleep 的 probs
bpftrace -l '*sleep*'
```
#### 对比
kprobe: 用于动态插入内核函数探针。适合调试和监控内核行为。
uprobe: 类似于 kprobe，但用于用户空间程序。适合调试和监控用户空间应用。
tracepoint: 预定义的跟踪点，适合稳定、低开销的监控。常用于内核和用户空间的特定事件监控。
perf_event: 强大的性能监控框架，适合全面的系统性能分析和调试。通过 perf 工具使用。
这些工具各有其适用场景，结合使用可以提供更全面和深入的系统性能和行为分析。
![img.png](/commons/其他/image/img4.png)


### Maps
这些 map 类型在 BPF 和 BPFtrace 中提供了灵活的数据存储和聚合能力，适用于各种性能监控和分析任务。
#### Associative Arrays

* 描述: 类似于哈希表，支持任意类型作为键。
* 用途: 统计计数、记录状态。
* 示例:

```sh
@syscall_count[comm] = count();
```

#### Histograms

* 描述: 用于生成直方图，自动计算分桶。
* 用途: 性能分布分析。
* 示例:

```sh
@latency = hist(latency);
```

#### Lateness Histograms (lhist)

* 描述: 类似于直方图，但支持用户自定义桶边界。
* 用途: 精确的延迟分布分析。
* 示例:

```sh
@latency = lhist(latency, 0, 100, 1);
```

#### Counters

* 描述: 用于简单计数。
* 用途: 事件计数。
* 示例:

```sh
@count++;
```

#### Sum, Min, Max, Avg

* 描述: 聚合操作，计算和、最小值、最大值和平均值。
* 用途: 数据汇总。
* 示例:

```sh
@total = sum(latency);
@min = min(latency);
@max = max(latency);
@avg = avg(latency);
```


#### 例子

```
1.-------------------
sudo bpftrace -e '
BEGIN {
    printf("Tracing function calls... Hit Ctrl-C to end.\n");
}

kprobe:do_sys_open {
    @start[tid] = nsecs;
}

kretprobe:do_sys_open {
    @time[tid] = nsecs - @start[tid];
    delete(@start[tid]);
}

interval:s:1 {
    print(@time);
    clear(@time);
}
'

2. -------------------
sudo bpftrace -e '
BEGIN {
    printf("Tracing syscalls... Hit Ctrl-C to end.\n");
}

tracepoint:syscalls:sys_enter_openat {
    @syscall_count[comm] = count();
}

END {
    printf("System call counts by process:\n");
    print(@syscall_count);
}
'


```

## Maps
#### Hash Map (BPF_MAP_TYPE_HASH)

* 描述: 基于哈希表的键值存储，适用于快速插入和查找操作。
* 用途: 通用键值存储，如统计计数、跟踪状态。
* 示例:

```c
struct bpf_map_def SEC("maps") my_hash_map = {
.type = BPF_MAP_TYPE_HASH,
.key_size = sizeof(int),
.value_size = sizeof(long),
.max_entries = 1024,
};
```

#### Array Map (BPF_MAP_TYPE_ARRAY)

* 描述: 固定大小的数组，每个索引存储一个值。
* 用途: 存储固定数量的元素，适用于计数器、配置参数。
* 示例:

```c
struct bpf_map_def SEC("maps") my_array_map = {
.type = BPF_MAP_TYPE_ARRAY,
.key_size = sizeof(int),
.value_size = sizeof(long),
.max_entries = 256,
};
```

#### Per-CPU Hash Map (BPF_MAP_TYPE_PERCPU_HASH)

* 描述: 类似于 BPF_MAP_TYPE_HASH，但每个 CPU 都有自己独立的哈希表。
* 用途: 减少竞争，适用于高并发环境。
* 示例:

```c
struct bpf_map_def SEC("maps") my_percpu_hash_map = {
.type = BPF_MAP_TYPE_PERCPU_HASH,
.key_size = sizeof(int),
.value_size = sizeof(long),
.max_entries = 1024,
};
```

#### Per-CPU Array Map (BPF_MAP_TYPE_PERCPU_ARRAY)

* 描述: 类似于 BPF_MAP_TYPE_ARRAY，但每个 CPU 都有自己独立的数组。
* 用途: 适用于需要高性能计数的场景。
* 示例:

```c
struct bpf_map_def SEC("maps") my_percpu_array_map = {
.type = BPF_MAP_TYPE_PERCPU_ARRAY,
.key_size = sizeof(int),
.value_size = sizeof(long),
.max_entries = 256,
};
```

#### Stack Trace Map (BPF_MAP_TYPE_STACK_TRACE)

* 描述: 存储内核或用户空间的调用栈。
* 用途: 调用栈追踪、性能分析。
* 示例:

```c
struct bpf_map_def SEC("maps") my_stack_trace_map = {
.type = BPF_MAP_TYPE_STACK_TRACE,
.key_size = sizeof(int),
.value_size = PERF_MAX_STACK_DEPTH * sizeof(__u64),
.max_entries = 128,
};
```

#### Ring Buffer Map (BPF_MAP_TYPE_RINGBUF)

* 描述: 环形缓冲区，适用于高效的事件传输。
* 用途: 事件追踪、日志记录。
* 示例:

```c
struct bpf_map_def SEC("maps") my_ringbuf_map = {
.type = BPF_MAP_TYPE_RINGBUF,
.max_entries = 4096,
};
```


### 手册
* https://github.com/bpftrace/bpftrace/blob/master/man/adoc/bpftrace.adoc
* 各种trace例子 -> https://github.com/bpftrace/bpftrace/blob/master/docs/tutorial_one_liners.md
