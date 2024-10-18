---
title: 5-Docker in Docker
date: 2023-05-17
categories: [笔记, '云原生', 'k8s其他']
tags: [云原生]
---

# Docker-in-Docker

## privileged

[do-not-use-dind-for-ci](/posts/do-not-use-dind-for-ci/)

Privileged模式：在Docker中，可以通过使用"--privileged"标志运行容器，使其获得对宿主机的完全权限。容器在此模式下具有更高的权限级别，可以执行特权操作，如加载内核模块和修改系统配置。这种模式下的容器可以直接访问宿主机的设备和文件系统。然而，使用privileged模式也带来了潜在的安全风险，因此应小心使用，并仅将其应用于受信任的容器和环境。

## sysbox

Sysbox：Sysbox是一个容器运行时工具，通过在容器内运行一个完整的操作系统来提供更高级的容器功能。通过使用Sysbox，容器内的进程可以获得与宿主机相同的权限级别，并执行需要系统级权限的操作。这种方法可以提供更广泛的操作自由度，但也增加了潜在的安全风险，因为容器内的进程具有与宿主机相同的权限。

## mount docker.sock

Mount docker.sock：这种方法是将Docker守护进程的UNIX套接字文件（docker.sock）挂载到容器内，使容器内的进程可以通过该套接字与Docker守护进程进行通信。这允许容器内的进程与Docker进行交互，例如创建、启动和管理其他容器。使用此方法，容器内的进程可以与Docker守护进程进行通信，但不会直接获得与宿主机相同的权限级别。

## Kanico

> Kaniko提供了一种在无需Docker守护进程和特权访问的情况下构建镜像的方式。它通过在用户空间中执行构建操作和禁用缓存来确保构建的可重复性和可移植性。这使得Kaniko在许多场景下成为一个有用的工具，特别是在CI/CD环境中进行镜像构建和推送的情况下。

### kanico vs docker
Kaniko和Docker在构建镜像的原理上有一些区别。

* 构建环境：Kaniko是一个独立的构建工具，它不需要依赖Docker守护进程来执行构建操作。相反，Kaniko在用户空间中直接执行镜像构建操作，而不需要特权访问或与Docker守护进程通信。

* 无需Docker守护进程：Kaniko可以在任何支持OCI（Open Container Initiative）规范的容器运行时环境中运行，而不仅限于Docker守护进程。这意味着你可以在Kubernetes、OpenShift等容器平台上使用Kaniko进行构建，而无需安装和配置Docker。

* 无缓存构建：Docker在构建镜像时会使用缓存机制来提高构建速度。如果前一层的命令没有改变，Docker会使用缓存的镜像层。然而，Kaniko默认情况下会禁用构建缓存，每个命令都会生成一个完整的镜像层，以确保构建的一致性和可重复性。

* 非特权操作：Kaniko在构建过程中不需要特权访问，这意味着可以在受限制的环境中运行，如CI/CD系统或多租户容器平台。相比之下，使用Docker进行构建通常需要特权访问权限。

