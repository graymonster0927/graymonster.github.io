---
title: grpc的keep alive和tcp的keep alive有什么区别
date: 2020-06-08
categories: [笔记, '网络', '零碎']
tags: [网络]
---

# grpc的keep alive和tcp的keep alive有什么区别

gRPC的 Keep-Alive和TCP的Keep-Alive都是用来检测连接是否存活，并防止连接空闲超时断开。它们的区别在于：

## 1. Keep-Alive触发的条件不同
  * TCP的Keep-Alive是基于TCP协议层的，只能检测TCP连接是否存活，而无法检测应用层的状态。当连接空闲一段时间后（默认2小时），TCP会自动发送Keep-Alive消息，如果一定次数（默认为9次）都没有收到对方的响应，TCP会断开连接。
  * gRPC的Keep-Alive是在应用层实现的，它会在客户端和服务器之间定期发送Ping消息，以便检测连接的状态。如果在一定时间内（默认为2小时）没有收到对方的响应，gRPC会尝试重新连接。


## 2. Keep-Alive的设置方式不同
  * TCP的Keep-Alive需要通过系统级别的配置来设置，例如在Linux系统下可以使用/proc/sys/net/ipv4/tcp_keepalive_*来配置TCP Keep-Alive。
  * gRPC的Keep-Alive可以在gRPC客户端和服务器的配置中进行设置，例如可以通过grpc.keepalive_time_ms设置Keep-Alive的间隔时间，通过grpc.keepalive_timeout_ms设置响应超时时间。


> 总的来说，gRPC的Keep-Alive能够更精细地控制连接的状态，并且可以在应用层级别上进行设置和控制，而TCP的Keep-Alive只能在系统级别上进行配置。
