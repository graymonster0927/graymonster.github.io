---
title: select和epoll
date: 2022-12-12
categories: [笔记, '网络', '零碎']
tags: [网络]
---

# select和epoll

两个都实现了io多路复用
select在每次select时候把所有fd都从用户空间复制到内核空间, 标记有事件的fd, 再把所有fd列表从内核空间复制到用户空间 然后遍历, <br>
epoll在每次 ctl 时候已经把当前fd从用户空间复制到了内核空间, 同时在内核空间维护一个红黑树, 当有事件时候, 会高效找到 fd, 然后组成一个list, 复制到用户空间<br>
对比下来, epoll用户/内核空间复制的开销明显降低, 特别是当 fd 非常多的时候<br>

epoll比select更高效的一点是：epoll监控的每一个文件fd就绪事件触发，导致相应fd上的回调函数ep_poll_callback()被调用<br>
