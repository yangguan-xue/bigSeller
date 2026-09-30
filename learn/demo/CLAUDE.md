# 学习项目规则

## 目标

参照大麦票务系统源码，在 `learn/demo/` 中逐步复现简历涉及的核心模块，用于面试准备。

## 构建顺序

```
第1步: damai-common 基础框架
   - 统一响应体 ApiResponse、响应码枚举 BaseCode
   - 异常体系（BaseException / DaMaiFrameException / ArgumentException）
   - 加密工具（AES / RSA加解密 / RSA签名验签 / Base64）
   - JWT Token 工具
   - Jackson 全局配置（日期格式、空值处理）
   - ThreadLocal 参数传递（BaseParameterHolder）
   - 全局常量、日期工具、字符串工具

第2步: Gateway 安全体系
   - RSA+AES 混合加密请求验签
   - 数字签名验证
   - JWT Token 鉴权
   - 令牌桶限流（RateLimiter）
   - 微服务请求头参数传递（traceId、userId、gray）

第3步: Redis Lua 原子扣减 + Kafka 异步下单
   - Redis Lua 脚本（库存扣减、数据回滚、座位查询）
   - Kafka 异步创建订单消费者
   - 多版本订单策略模式（V1-V4）

第4步: 分布式锁 + 延迟队列
   - @ServiceLock 注解 + AOP 切面实现
   - 锁工具类（有返回值/无返回值）
   - 锁工厂 + 多种锁类型
   - Redisson 延迟队列（订单超时取消）

第5步: 多级缓存架构
   - Caffeine 本地缓存（节目、票档等）
   - Redis 分布式缓存
   - 读写锁 + 双重检测防缓存击穿
   - Redis Stream 缓存失效通知

第6步: Elasticsearch 搜索引擎
   - ES 基础框架封装
   - 节目搜索、主页查询、推荐列表

第7步: ShardingSphere 分库分表
   - 基因法分库算法
   - 基因法分表算法
   - 在线数据迁移

第8步: 灰度发布（可选扩展）
   - 灰度负载均衡过滤
   - Gateway/WebMvc 双模式上下文处理
```

## 每次构建要求

1. 先阅读大麦源码对应模块，理解设计思路
2. 在 demo 中从零搭建，不直接拷贝源码
3. 每步完成后运行测试验证
4. 对比与源码的差异，思考为什么这样设计

## 技术栈

- Spring Boot 4.0.6 + Java 17
- Maven 多模块
- Lombok
