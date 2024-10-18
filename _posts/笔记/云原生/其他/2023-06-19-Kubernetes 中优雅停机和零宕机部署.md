---
title: k8s中优雅停机和零宕机部署(endpoint事件流程)
date: 2023-06-19
categories: [笔记, '云原生', 'k8s其他']
tags: [云原生]
---

# k8s中优雅停机和零宕机部署(endpoint事件流程)

在 Kubernetes 中，创建、删除 Pod 可以说是最常见的任务之一。当我们进行滚动更新、扩展部署等等，都会创建 Pod。
另外，在我们将节点标记为不可调度时，Pod 被驱逐后也会被删除并重新创建。这些 Pod 的生命周期非常短暂，如果 Pod 还在响应请求的过程中，就被关闭了会怎么样？

* 关闭前的请求是否已完成？
* 接下来的请求又如何呢？
* 在讨论删除 Pod 时会发生什么之前，我们需要知道在创建 Pod 时会发生什么。假设我们在集群中创建了以下 Pod：

![6(1).png](/commonts/云原生/其他/image/6(1).png)

我们将Pod YAML 定义提交给集群：kubectl apply -f pod.yaml

在输入命令后，kubectl 就会将 Pod 定义提交给 Kubernetes API。



## 在数据库中保存集群状态

API 接收并检查 Pod 定义，然后将其存储在 etcd 数据库中。另外，Pod 将被添加到调度程序的队列中。
调度程序会检查 Pod 定义，再收集有关工作负载的详细信息，例如 CPU 和内存请求，然后确定哪个节点最适合运行它。在调度程序结束后：
* 
* 在 etcd 中的 Pod 会被标记为 Scheduled。
* Pod 被分配到一个节点。
* Pod 的状态会存储在 etcd 中。
* 
但是 Pod 此时仍然是不存在的，因为之前的任务都发生在控制平面中，Pod 状态仅存储在数据库中。那么我们要如何在节点中创建 Pod？


## Kubelet

kubelet 的工作是轮询控制平面以获取更新。kubelet 不会自行创建 Pod，而是将工作交给其他三个组件：

* 容器运行时接口（CRI）：为 Pod 创建容器的组件。
* 容器网络接口（CNI）：将容器连接到集群网络并分配 IP 地址的组件。
* 容器存储接口（CSI）：在容器中装载卷的组件。
* 在大多数情况下，容器运行时接口（CRI）的工作类似于：docker run -d cotainer


### 容器网络接口（CNI）负责：

* 为 Pod 生成有效的 IP 地址。
* 将容器连接到网络。
* 我们有多种方法可以将容器连接到网络并分配有效的 IP 地址，我们可以在 IPv4 或 IPv6 之间进行选择，也可以分配多个 IP 地址。当容器网络接口完成其工作时，Pod 也连接到网络，并分配了有效的IP地址。这里会出现一个问题，Kubelet 知道 IP 地址，因为它调用了容器网络接口，但是控制平面不知道。主节点也不知道该 Pod 已经被分配了 IP 地址，并准备接收流量。单纯从控制平面的角度来看，现在仍在创建 Pod 阶段 。kubelet 的工作是收集 Pod 的所有详细信息，例如 IP 地址，并将其报告回控制平面。我们检查 etcd 不仅可以显示 Pod 的运行位置，还可以显示其 IP 地址。

如果 Pod 不是任何 Service 的一部分，那到这里就结束了，因为 Pod 已经创建完毕并可以使用，但如果 Pod 是 Service 的一部分，那还有几个步骤需要执行。


## Pod 和 Service

在创建 Service 时，我们需要注意两点信息：

* selector：指定接收流量的 Pod。
* targetPort：通过 Pod 端口接收流量。

Service 的 YAML 定义如下：
![6(2).png](/commonts/云原生/其他/image/6(2).png)


我们使用 kubectl apply 将 Service 提交给集群时，Kubernetes 会找到所有和选择器（name: app）有着相同标签的 Pod，并收集其 IP 地址，当然它们需要先通过 Readiness 探针，然后再将每个 IP 地址都和端口连接在一起。如果 IP 地址是 10.0.0.3，targetPort 是 3000，Kubernetes 会将这两个值连接起来称为 endpoint。

endpoint 会存储在 etcd 的一个名为 Endpoint 的对象中。这里有点要注意：

* endpoint（e 小写）=IP 地址 + 端口（10.0.0.3:3000）。
* Endpoint（E 大写）是 endpiont 的集合。

Endpoint 对象是 Kubernetes 中的真实对象，对于每个 Service，Kubernetes 都会自动创建一个 Endpoint 对象。我们可以使用以下方法进行验证：

![6(3).png](/commonts/云原生/其他/image/6(3).png)

Endpoint 对象会从 Pod 中收集所有的 IP 地址和端口，而且不仅一次。在以下情况中，Endpoint 对象将更新一个 endpiont 新列表：

* Pod 创建时。
* Pod 删除时。
* 在 Pod 上修改标签时。

因此，每次在创建 Pod 并在 kubelet 将其 IP 地址发送到主节点后，Kubernetes 都会更新所有 endpoint：
![6(4).png](/commonts/云原生/其他/image/6(4).png)

endpoint 存储在控制平面中，Endpoint 对象也会更新。



## 在 Kubernetes 中使用 endpoint

### endpoint 被 Kubernetes 中的多个组件所使用。
Kube-proxy 使用 endpoint 在节点上设置 iptables 规则。因此，每次对 Endpoint 对象进行更改时，kube-proxy 都会检索 IP 地址和 endpiont 新列表，以编写新的 iptables 规则。
Ingress 控制器也使用相同的 endpiont 列表。Ingress 控制器是集群中将外部流量路由到集群中的组件。在设置 Ingress 列表时，我们通常将 Service 指定为目标：
![6(5).png](/commonts/云原生/其他/image/6(5).png)

实际上，流量不会路由到 Service，Ingress 控制器设置了 subscription，每次该 Service 的 endpoint 更改时都将收到通知，所以，Ingress 会将流量直接路由到 Pod，从而跳过 Service。可以想象，每次更改 Endpoint 对象时，Ingress 都会检索 IP 地址和 endpoint 新列表，并将控制器重新配置。现在我们快速回顾一下创建 Pod 时发生的过程：1.Pod 先存储在 etcd 中。2.调度程序会分配一个节点，再将节点写入 etcd。3.向 kubelet 通知有个新 Pod。4.kubelet 将创建容器的任务给CRI。5.kubelet 将容器附加到 CNI。6.kubelet 将容器中的卷委派给 CSI。7.CNI 分配 IP 地址。8.Kubelet 将 IP 地址通知给控制平面。9.IP 地址存储在 etcd 中。如果我们的 Pod 属于 Service：1.Kubelet 等待 Readiness 探针成功。2.对所有相关的 Endpoint 对象更改进行通知。3.Endpoint 将新 endpoint（IP 地址 + 端口）添加到列表中。4.Kube-proxy 被通知 Endpoint 更改，然后 Kube-proxy 会更新每个节点上的 iptables 规则。5.Ingress 控制器被通知 Endpoint 变化，然后控制器会将流量路由到新的 IP 地址。6.CoreDNS 被通知 Endpoint 更改。如果服务的类型为 Headless，DNS 会进行更新。7.云提供商被通知 Endpoint 更改。如果 Service 是 type: LoadBalancer，新的 endpoint 配置会是负载均衡池的一部分。8.集群中安装的所有服务网格也会被通知 Endpoint 更改。9.订阅 Endpoint 更改的其他运营商也会收到通知。虽然列表很长，实际上这就是一项常见任务：创建一个 Pod。Pod 已经成功运行了，下面我们讨论删除时会发生什么。

### 删除 Pod

删除 Pod 时，我们要遵循上文相同的步骤，不过是相反的。首先，我们从 Endpoint 对象中删除 endpiont，但这次“readiness”探针会被忽略，endpiont 会立即从控制平面中移除，然后再依次触发所有事件到 kube-proxy，Ingress 控制器、DNS、服务网格等。这些组件将更新其内部状态，并停止将流量路由到 IP 地址。

由于组件可能忙于执行其他操作，因此无法保证从其内部状态中删除 IP 地址将花费多长时间。有时候这可能不到一秒钟，但有时候可能需要更多时间。同时，etcd 中 Pod 的状态会更改为 Termination。kubelet 会被通知此次更改：1.连接 CSI 的卷将从容器中卸载。2.从网络上分离容器并将 IP 地址释放到 CNI。3.将容器销毁到 CRI。换句话说，此时 Kubernetes 会遵循与创建 Pod 完全相同但反向的步骤。实际上，这存在着细微的差异。当我们终止 Pod 时，将同时删除 endpoint 和发送到 kubelet 的信号。

创建 Pod 时，Kubernetes 会等待 kubelet 报告 IP 地址，然后进行 endpoint 广播，但删除 Pod 时，这些事件是并行开始的。这可能会导致一些条件竞争。如果在 endpoint 广播之前删除Pod怎么办？



### 优雅停机

当 Pod 在 kube-proxy 或 Ingress 控制器删除之前终止，我们可能会遇到停机时间。此时，Kubernetes 仍将流量路由到 IP 地址，但 Pod 已经不存在了。Ingress 控制器、kube-proxy、CoreDNS 等也没有足够的时间从其内部状态中删除 IP地址。
理想情况下，在删除 Pod 之前，Kubernetes 应该等待集群中的所有组件更新了 endpoint 列表，但是 Kubernetes 不是那样工作的。Kubernetes 提供了原语来分发 endpoint（即 Endpoint 对象和更高级的抽象，例如 Endpoint Slices），所以 Kubernetes 不会验证订阅 endpoint 更改的组件是否是最新的集群状态信息。那么，如何避免这种竞争情况并确保在 endpoint 广播之后删除 Pod？我们需要等待，当 Pod 即将被删除时，它会收到 SIGTERM 信号。我们的应用程序可以捕获该信号并开始关闭。由于 endpoint 不会立即从 Kubernetes 的所有组件中删除，所以我们可以：1.请稍等片刻，然后退出。2.即便有 SIGTERM 信号，但仍然可以处理传入流量。3.最后，关闭现有的长期连接。4.关闭该进程。那么我们应该等多久？默认情况下，Kubernetes 将发送 SIGTERM 信号并等待 30 秒，然后强制终止该进程。因此，我们可以使用前 15 秒继续操作。该间隔应足以将 endpoint 删除信息传播到 kube-proxy、Ingress 控制器、CoreDNS 等，然后，到达 Pod 的流量会越来越少，直到停止。15 秒后，我们就可以安全地关闭与数据库的连接并终止该过程。如果我们认为需要更多时间，那么可以在 20 或 25 秒时停止该过程。这里有一点要注意，Kubernetes 将在 30 秒后强行终止该进程（除非我们更改 Pod 定义中的 terminationGracePeriodSeconds）。如果我们无法更改代码以获得更长的等待时间要怎么办？我们可以调用脚本以获得固定的等待时间，然后退出应用程序。在调用 SIGTERM 之前，Kubernetes 会在 Pod 中公开一个 preStop hook。我们可以将 preStop hook 设置为等待 15 秒。下面是一个例子：
![6(6).png](/commonts/云原生/其他/image/6(6).png)

preStop hook 是 Pod LifeCycle hook 之一。



### 宽限期和滚动更新

优雅停机适用于要删除的 Pod，但如果我们不删除 Pod，会怎么样？其实即使我们不做，Kubernetes 也会删除 Pod。在每次部署较新版本的应用程序时，Kubernetes 都会创建、删除 Pod。

在 Deployment 中更改镜像像时，Kubernetes 会逐步进行更改。
![6(7).png](/commonts/云原生/其他/image/6(7).png)


如果我们有三个副本，并提交新的 YAML 资源，Kubernetes 会：

1.用新的容器镜像创建一个 Pod。

2.销毁现有的 Pod。

3.等待 Pod 准备就绪。

它会不断重复上述步骤，直到将所有 Pod 迁移到较新的版本。Kubernetes 在新 Pod 准备接收流量之后会重复每个周期。另外，Kubernetes 不会在转移 Pod 前等待 Pod 被删除。如果我们有 10 个 Pod，并且 Pod 需要 2 秒钟的准备时间和 20 秒的关闭时间，就会发生以下情况：

1.创建一个 Pod，终止前一个 Pod。

2.Kubernetes 创建一个新的 Pod 后，需要 2 秒钟的准备时间。

3.同时，被终止的 Pod 会有 20 秒的停止时间。

20 秒后，所有新 Pod 均已启用，之前的 10 个 Pod 都将终止。这样，我们在短时间内将 Pod 的数量增加了一倍（运行 10 次，终止 10 次）。宽限期越长，同时具有“运行”和“终止”的 Pod 也就越多。


### 终止长时间运行的任务

如果我们要对大型视频进行转码，是否有任何方法可以延迟停止 Pod？

假设我们有一个包含三个副本的 Deployment。每个副本都分配了一个视频转码任务，该任务可能需要几个小时才能完成。当我们触发滚动更新时，Pod 会在 30 秒内完成任务，然后将其杀死。如何避免延迟关闭 Pod？我们可以将其 terminationGracePeriodSeconds 增加到几个小时，但这样 Pod 的 endpoint 将 unreachable。如果我们公开指标以监控 Pod，instrumentation 将无法访问 Pod。Prometheus 之类的工具依赖于 Endpoints 在集群中 scrape Pod。一旦删除 Pod，endpoint 删除信息就会在集群中传播，甚至传播到 Prometheus。我们应该为每个新版本创建一个新的 Deployment，而不是增加宽限期。当我们创建全新的 Deployment 时，现有的 Deployment 将保持不变。长时间运行的作业可以照常继续处理视频，在完成后，我们可以手动删除。

如果想自动删除，那我们可以需要设置一个自动伸缩器，当它们完成任务时，可以将 Deployment 扩展到零个副本。


# 总结

我们应该注意 Pod 从集群中删除后，它们的 IP 地址可能仍用于路由流量。相比立即关闭 Pod，我们不如在应用程序中等待一下或设置一个 preStop hook。在 endpoint 传播到集群中，并且 Pod 从 kube-proxy、Ingress 控制器、CoreDNS 等中删除后，Pod 才算被移除。

如果我们的 Pod 运行诸如视频转码之类的长期任务，可以考虑使用 Rainbow 部署。在 Rainbow 部署中，我们会为每个发行版创建一个新的 Deployment，并在任务完成后删除上一个发行版。原文地址：https://learnk8s.io/graceful-shutdown

# 全文拷贝自 -> https://www.cnblogs.com/cheyunhua/p/13646564.html
