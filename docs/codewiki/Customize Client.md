# Customize Client 模块 - 定制化规则管理客户端

## 1. 模块简介

Customize Client 模块是大麦系统中**定制化服务（Customize Service）的 RPC 数据模型模块**，位于 `damai-server-client/damai-customize-client`。该模块定义了一系列 **DTO（数据传输对象）** 和 **VO（视图对象）**，用于与 Customize Service 进行数据交互，核心功能围绕 **API 限流规则管理** 展开，包括**普通规则（Rule）**、**深度规则（DepthRule）**、**广播调用（BroadcastCall）** 和 **API 调用记录查询（ApiData）** 四大功能域。

### 1.1 核心功能

| 功能分类 | 说明 |
|---------|------|
| **普通规则管理** | 基于统计时间和阈值的简单 API 限流规则（Rule）的添加、查询、更新、状态修改 |
| **深度规则管理** | 基于时间窗口的进阶版 API 限流规则（DepthRule）的管理，支持多个时间窗口嵌套 |
| **全部规则管理** | 将普通规则与多条深度规则组合为统一的规则集进行管理 |
| **广播调用** | 向指定的微服务发送广播请求（用于规则刷新、缓存更新等场景） |
| **API 调用记录查询** | 分页查询被限流的 API 调用记录，支持按时间范围、IP、URL 等条件筛选 |

### 1.2 模块定位

```mermaid
graph TB
    subgraph "系统架构中的定位"
        direction TB
        
        Gateway[Gateway Service<br/>网关服务 - 限流执行方]
        CustomizeService[Customize Service<br/>定制化服务 - 规则管理方]
        CustomizeClient[Customize Client<br/>定制化客户端 - 数据模型]
        Redis[Redis 缓存<br/>规则数据共享]
        Common[Common 模块<br/>公共基础库]
        Kafka[Kafka 消息队列<br/>API 调用记录异步传输]
        
        Gateway -->|读取规则| Redis
        Gateway -->|发送限流记录| Kafka
        CustomizeService -->|写入规则| Redis
        CustomizeService <-->|使用 DTO/VO| CustomizeClient
        CustomizeService --> Common
        Gateway --> Common
        Kafka -->|消费记录| CustomizeService
    end
```

### 1.3 与 Gateway Service 的关系

Customize Client 与 Gateway Service 之间存在紧密的协作关系，共同构成了系统的 **API 限流体系**：

```mermaid
graph LR
    subgraph "限流体系架构"
        Admin[管理员/后台系统]
        CustomizeService[Customize Service<br/>规则管理]
        CustomizeClient[Customize Client<br/>DTO/VO 数据模型]
        GatewayService[Gateway Service<br/>限流执行引擎]
        RedisCache[(Redis 缓存<br/>规则数据)]
        LuaScript[Lua 脚本<br/>限流算法]
        
        Admin -->|配置规则| CustomizeService
        CustomizeService -->|使用 DTO| CustomizeClient
        CustomizeService -->|存入| RedisCache
        GatewayService -->|读取| RedisCache
        GatewayService -->|执行| LuaScript
        LuaScript -->|返回结果| GatewayService
        GatewayService -->|触发限流| Admin[返回错误]
    end
```

## 2. 架构设计

### 2.1 模块架构图

```mermaid
graph TB
    subgraph "Customize Client 模块"
        direction TB
        
        subgraph "数据传输对象（DTO）"
            AllRuleDto[AllRuleDto<br/>全部规则 DTO]
            RuleDto[RuleDto<br/>普通规则 DTO]
            RuleGetDto[RuleGetDto<br/>普通规则查询]
            RuleUpdateDto[RuleUpdateDto<br/>普通规则更新]
            RuleStatusDto[RuleStatusDto<br/>普通规则状态修改]
            DepthRuleDto[DepthRuleDto<br/>深度规则 DTO]
            DepthRuleUpdateDto[DepthRuleUpdateDto<br/>深度规则更新]
            DepthRuleStatusDto[DepthRuleStatusDto<br/>深度规则状态修改]
            BroadcastCallDto[BroadcastCallDto<br/>广播调用 DTO]
            ApiDataDto[ApiDataDto<br/>API 调用记录查询]
        end
        
        subgraph "返回对象（VO）"
            AllDepthRuleVo[AllDepthRuleVo<br/>全部规则 VO]
            RuleVo[RuleVo<br/>普通规则 VO]
            DepthRuleVo[DepthRuleVo<br/>深度规则 VO]
            ApiDataVo[ApiDataVo<br/>API 调用记录 VO]
        end
        
        AllRuleDto --> RuleDto
        AllRuleDto --> DepthRuleDto
        AllDepthRuleVo --> RuleVo
        AllDepthRuleVo --> DepthRuleVo
    end
    
    subgraph "外部依赖"
        Common[Common 模块<br/>ApiResponse / 工具类]
        Swagger[Swagger 3<br/>OpenAPI 文档注解]
        Validation[Jakarta Validation<br/>参数校验注解]
    end
    
    CustomizeClient --> Swagger
    CustomizeClient --> Validation
    CustomizeClient --> Lombok[Lombok]
```

### 2.2 模块依赖关系

```mermaid
graph LR
    subgraph "依赖关系"
        direction LR
        CustomizeClient[Customize Client]
        
        CustomizeClient --> Lombok[Lombok]
        CustomizeClient --> Swagger[Swagger 3 / OpenAPI]
        CustomizeClient --> Validation[Jakarta Validation]
        CustomizeClient --> Jackson[Jackson Annotations]
        
        CustomizeService[Customize Service] -.->|使用 DTO/VO| CustomizeClient
        GatewayService[Gateway Service] -.->|使用 VO 读取规则| CustomizeClient
        AdminService[Admin Service] -.->|管理后台可能使用| CustomizeClient
    end
```

> **注意**：不同于其他 Client 模块（如 `Base Data Client`），Customize Client **不包含 Feign 客户端接口声明**。它纯粹作为**数据模型库（DTO/VO）** 被 Customize Service 使用（服务端接收参数和返回响应），同时其 VO 类也被 Gateway Service 引用（从 Redis 读取规则数据时反序列化使用）。

### 2.3 规则类型体系

```mermaid
classDiagram
    class RuleDto {
        +Integer statTime
        +Integer statTimeType
        +Integer threshold
        +Integer effectiveTime
        +Integer effectiveTimeType
        +String limitApi
        +String message
    }
    
    class DepthRuleDto {
        +String startTimeWindow
        +String endTimeWindow
        +Integer statTime
        +Integer statTimeType
        +Integer threshold
        +Integer effectiveTime
        +Integer effectiveTimeType
        +String limitApi
        +String message
        +Integer status
    }
    
    class AllRuleDto {
        +RuleDto ruleDto
        +List~DepthRuleDto~ depthRuleDtoList
    }
    
    class RuleVo {
        +Long id
        +Integer statTime
        +Integer statTimeType
        +Integer threshold
        +Integer effectiveTime
        +Integer effectiveTimeType
        +String limitApi
        +String message
        +Integer status
        +Date createTime
    }
    
    class DepthRuleVo {
        +Long id
        +String startTimeWindow
        +String endTimeWindow
        +Integer statTime
        +Integer statTimeType
        +Integer threshold
        +Integer effectiveTime
        +Integer effectiveTimeType
        +String limitApi
        +String message
        +Integer status
        +Date createTime
        +Long startTimeWindowTimestamp
        +Long endTimeWindowTimestamp
    }
    
    class AllDepthRuleVo {
        +RuleVo ruleVo
        +List~DepthRuleVo~ depthRuleVoList
    }
    
    AllRuleDto --> RuleDto : 包含
    AllRuleDto --> DepthRuleDto : 包含列表
    AllDepthRuleVo --> RuleVo : 包含
    AllDepthRuleVo --> DepthRuleVo : 包含列表
    
    RuleDto <-- RuleVo : 响应映射
    DepthRuleDto <-- DepthRuleVo : 响应映射
```

## 3. 核心组件详解

### 3.1 普通规则（Rule）

普通规则是最基础的 API 限流规则，基于**统计时间 + 阈值**的模式进行限流判断。

#### 3.1.1 RuleDto（普通规则参数）

**作用**：用于创建/添加普通规则的请求参数。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `statTime` | Integer | `@NotNull` | 统计时间，单位由 `statTimeType` 决定 |
| `statTimeType` | Integer | `@NotNull` | 统计时间类型：1=秒，2=分钟 |
| `threshold` | Integer | `@NotNull` | 阈值，超过此数量则触发限流 |
| `effectiveTime` | Integer | `@NotNull` | 规则生效限制时间（触发限流后的封禁时长） |
| `effectiveTimeType` | Integer | `@NotNull` | 生效时间类型：1=秒，2=分钟 |
| `limitApi` | String | 可选 | 限制的 API 路径（为空则对所有 API 生效） |
| `message` | String | 可选 | 触发限流时的提示信息 |

**限流逻辑示例**：`statTime=10, statTimeType=1, threshold=100, effectiveTime=30, effectiveTimeType=1` → 在 10 秒内超过 100 次调用，则限流 30 秒。

#### 3.1.2 RuleGetDto（普通规则查询）

**作用**：根据 ID 查询普通规则的请求参数。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | Long | `@NotNull` | 普通规则 ID |

#### 3.1.3 RuleUpdateDto（普通规则更新）

**作用**：更新普通规则的请求参数，各字段均为可选（仅更新非空字段）。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | Long | `@NotNull` | 普通规则 ID（必填） |
| `statTime` | Integer | 可选 | 统计时间 |
| `statTimeType` | Integer | 可选 | 统计时间类型 |
| `threshold` | Integer | 可选 | 阈值 |
| `effectiveTime` | Integer | 可选 | 规则生效限制时间 |
| `effectiveTimeType` | Integer | 可选 | 生效限制时间类型 |
| `limitApi` | String | 可选 | 限制的 API 路径 |
| `message` | String | 可选 | 提示信息 |

#### 3.1.4 RuleStatusDto（普通规则状态修改）

**作用**：修改普通规则启用/禁用状态的请求参数。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | Long | `@NotNull` | 普通规则 ID |
| `status` | Integer | `@NotNull` | 状态：1=生效，0=禁用 |

#### 3.1.5 RuleVo（普通规则返回）

**作用**：普通规则的响应/视图对象。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | Long | 规则 ID |
| `statTime` | Integer | 统计时间 |
| `statTimeType` | Integer | 统计时间类型 |
| `threshold` | Integer | 阈值 |
| `effectiveTime` | Integer | 规则生效限制时间 |
| `effectiveTimeType` | Integer | 生效限制时间类型 |
| `limitApi` | String | 限制的 API 路径 |
| `message` | String | 提示信息 |
| `status` | Integer | 状态：1=生效，0=禁用 |
| `createTime` | Date | 创建时间 |

### 3.2 深度规则（DepthRule）

深度规则是普通规则的进阶版，增加了**时间窗口（startTimeWindow / endTimeWindow）** 维度，支持在特定时间段内按不同阈值进行限流。

#### 3.2.1 DepthRuleDto（深度规则参数）

**作用**：用于创建/添加深度规则的请求参数。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `startTimeWindow` | String | `@NotBlank` | 开始时间窗口，格式如 `HH:mm:ss` |
| `endTimeWindow` | String | `@NotBlank` | 结束时间窗口，格式如 `HH:mm:ss` |
| `statTime` | Integer | `@NotNull` | 统计时间 |
| `statTimeType` | Integer | `@NotNull` | 统计时间类型：1=秒，2=分钟 |
| `threshold` | Integer | `@NotNull` | 阈值 |
| `effectiveTime` | Integer | `@NotNull` | 规则生效限制时间 |
| `effectiveTimeType` | Integer | `@NotNull` | 生效限制时间类型：1=秒，2=分钟 |
| `limitApi` | String | 可选 | 限制的 API 路径 |
| `message` | String | 可选 | 提示信息 |
| `status` | Integer | 可选 | 状态：1=正常，0=失效 |

**深度规则特点**：
- **时间窗口限定**：规则仅在 `startTimeWindow ~ endTimeWindow` 时间段内生效（如 `10:00:00 ~ 12:00:00`）
- **多条规则组合**：可配置多个时间窗口，每个窗口有不同的限流阈值
- **与普通规则协同**：同时配置普通规则和深度规则时，按"深度规则"模式执行，取匹配时间窗口的规则进行限流

#### 3.2.2 DepthRuleUpdateDto（深度规则更新）

**作用**：更新深度规则的请求参数。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | Long | `@NotNull` | 深度规则 ID（必填） |
| `startTimeWindow` | String | 可选 | 开始时间窗口 |
| `endTimeWindow` | String | 可选 | 结束时间窗口 |
| `statTime` | Integer | 可选 | 统计时间 |
| `statTimeType` | Integer | 可选 | 统计时间类型 |
| `threshold` | Integer | 可选 | 阈值 |
| `effectiveTime` | Integer | 可选 | 规则生效限制时间 |
| `effectiveTimeType` | Integer | 可选 | 生效限制时间类型 |
| `limitApi` | String | 可选 | 限制的 API 路径 |
| `message` | String | 可选 | 提示信息 |
| `status` | Integer | 可选 | 状态：1=生效，0=禁用 |

#### 3.2.3 DepthRuleStatusDto（深度规则状态修改）

**作用**：修改深度规则启用/禁用状态的请求参数。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | Long | `@NotNull` | 深度规则 ID |
| `status` | Integer | `@NotNull` | 状态：1=生效，0=禁用 |

#### 3.2.4 DepthRuleVo（深度规则返回）

**作用**：深度规则的响应/视图对象。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | Long | 规则 ID |
| `startTimeWindow` | String | 开始时间窗口（`HH:mm:ss`） |
| `endTimeWindow` | String | 结束时间窗口（`HH:mm:ss`） |
| `statTime` | Integer | 统计时间 |
| `statTimeType` | Integer | 统计时间类型 |
| `threshold` | Integer | 阈值 |
| `effectiveTime` | Integer | 规则生效限制时间 |
| `effectiveTimeType` | Integer | 生效限制时间类型 |
| `limitApi` | String | 限制的 API 路径 |
| `message` | String | 提示信息 |
| `status` | Integer | 状态：1=生效，0=禁用 |
| `createTime` | Date | 创建时间 |
| `startTimeWindowTimestamp` | Long | 开始时间窗口的时间戳（运行时计算，非持久化字段） |
| `endTimeWindowTimestamp` | Long | 结束时间窗口的时间戳（运行时计算，非持久化字段） |

> **注**：`startTimeWindowTimestamp` 和 `endTimeWindowTimestamp` 是运行时由 Gateway Service 的 `ApiRestrictService` 将时间字符串转为当天的时间戳（毫秒），用于 Lua 脚本中的时间窗口匹配判断。

### 3.3 全部规则（AllRule）

#### 3.3.1 AllRuleDto（全部规则参数）

**作用**：同时包含普通规则和多条深度规则的复合请求参数，用于一次性配置完整的规则集。

```java
@Data
@Schema(title="AllRuleDto", description ="全部规则")
public class AllRuleDto {
    @NotNull
    private RuleDto ruleDto;              // 必填：普通规则
    
    private List<DepthRuleDto> depthRuleDtoList;  // 可选：深度规则列表
}
```

#### 3.3.2 AllDepthRuleVo（全部规则返回）

**作用**：全部规则的复合响应对象。

| 字段 | 类型 | 说明 |
|------|------|------|
| `ruleVo` | RuleVo | 普通规则信息 |
| `depthRuleVoList` | List\<DepthRuleVo\> | 深度规则列表 |

### 3.4 广播调用（BroadcastCall）

#### 3.4.1 BroadcastCallDto（广播调用参数）

**作用**：向指定微服务广播发送消息的请求参数，用于规则变更后的缓存刷新通知。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `serviceName` | String | `@NotBlank` | 目标服务名（如 `damai-gateway-service`） |
| `requestBody` | String | `@NotBlank` | 请求体内容（JSON 格式字符串） |

**使用场景**：
- 规则变更后，通过广播通知各服务实例刷新本地/Redis 缓存
- 强制清除限流统计数据
- 服务间的事件通知

### 3.5 API 调用记录（ApiData）

#### 3.5.1 ApiDataDto（API 调用记录查询参数）

**作用**：分页查询 API 被限流调用记录的请求参数。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `pageNo` | Integer | `@NotNull` | 页码 |
| `pageSize` | Integer | `@NotNull` | 每页大小 |
| `startDate` | String | 可选 | 开始日期，格式 `yyyy-MM-dd HH:mm:ss` |
| `endDate` | String | 可选 | 结束日期，格式 `yyyy-MM-dd HH:mm:ss` |
| `apiAddress` | String | 可选 | API 请求的 IP 地址（筛选条件） |
| `apiUrl` | String | 可选 | API 路径（筛选条件） |

#### 3.5.2 ApiDataVo（API 调用记录返回）

**作用**：API 被限流调用记录的视图对象。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | Long | 记录 ID |
| `headVersion` | String | 请求头版本号 |
| `apiAddress` | String | 请求 IP 地址 |
| `apiMethod` | String | HTTP 方法（GET/POST） |
| `apiBody` | String | 请求体内容 |
| `apiParams` | String | 请求参数 |
| `apiUrl` | String | API 路径 |
| `createTime` | Date | 创建/记录时间 |
| `status` | Integer | 触发限流的规则类型 |
| `callDayTime` | String | 按天统计时间（`yyyy-MM-dd`） |
| `callHourTime` | String | 按小时统计时间（`yyyy-MM-dd HH`） |
| `callMinuteTime` | String | 按分钟统计时间（`yyyy-MM-dd HH:mm`） |
| `callSecondTime` | String | 按秒统计时间（`yyyy-MM-dd HH:mm:ss`） |

> **注**：Gateway Service 的 `ApiRestrictService.saveApiData()` 方法在触发限流时，会通过 Kafka 发送 `ApiDataDto` 消息，Customize Service 的 `ApiDataMessageConsumer` 消费消息后入库。`callDayTime` / `callHourTime` / `callMinuteTime` / `callSecondTime` 字段用于不同粒度的统计查询。

## 4. 数据流与交互

### 4.1 规则配置完整流程

```mermaid
sequenceDiagram
    participant Admin as 管理员/后台
    participant CustomizeCtrl as Customize Service<br/>Controller
    participant CustomizeSvc as Customize Service<br/>Service
    participant DB as MySQL
    participant Redis as Redis 缓存
    participant Gateway as Gateway Service<br/>(限流执行)
    
    Note over Admin,Gateway: 配置普通规则
    Admin->>CustomizeCtrl: POST /rule/add (RuleDto)
    CustomizeCtrl->>CustomizeSvc: ruleAdd()
    CustomizeSvc->>DB: INSERT INTO rule ...
    CustomizeSvc->>Redis: HSET ALL_RULE_HASH RULE → RuleVo
    CustomizeSvc-->>Admin: 返回成功
    
    Note over Admin,Gateway: 配置深度规则
    Admin->>CustomizeCtrl: POST /depthRule/add (DepthRuleDto)
    CustomizeCtrl->>CustomizeSvc: depthRuleAdd()
    CustomizeSvc->>DB: INSERT INTO depth_rule ...
    CustomizeSvc->>Redis: HSET ALL_RULE_HASH DEPTH_RULE → List<DepthRuleVo>
    CustomizeSvc-->>Admin: 返回成功
    
    Note over Admin,Gateway: 批量配置全部规则
    Admin->>CustomizeCtrl: POST /allRule/add (AllRuleDto)
    CustomizeCtrl->>CustomizeSvc: add()
    CustomizeSvc->>DB: INSERT INTO rule + depth_rule
    CustomizeSvc->>Redis: HSET ALL_RULE_HASH (批量更新)
    CustomizeSvc-->>Admin: 返回成功
    
    Note over Admin,Gateway: 规则变更后广播通知
    Admin->>CustomizeCtrl: POST /broadcast/add (BroadcastCallDto)
    CustomizeCtrl->>CustomizeSvc: call()
    CustomizeSvc->>Gateway: 广播调用服务实例
    Gateway->>Redis: 重新加载规则到本地
    CustomizeSvc-->>Admin: 返回成功
```

### 4.2 网关层限流执行流程

```mermaid
sequenceDiagram
    participant Client as 外部客户端
    participant GatewayFilter as Gateway Service<br/>RequestValidationFilter
    participant ApiRestrict as Gateway Service<br/>ApiRestrictService
    participant Redis as Redis
    participant Lua as Redis Lua 脚本
    participant Kafka as Kafka
    participant Customize as Customize Service
    
    Client->>GatewayFilter: HTTP 请求
    GatewayFilter->>ApiRestrict: apiRestrict(id, url, request)
    
    ApiRestrict->>Redis: HGET ALL_RULE_HASH RULE
    Redis-->>ApiRestrict: RuleVo (JSON)
    
    ApiRestrict->>Redis: HGET ALL_RULE_HASH DEPTH_RULE
    Redis-->>ApiRestrict: List<DepthRuleVo> (JSON)
    
    alt 无规则
        ApiRestrict-->>GatewayFilter: 通过，不限制
    else 仅普通规则
        ApiRestrict->>ApiRestrict: 构建 rule 参数
        ApiRestrict->>Lua: apiRuleOperate(parameters)
        Lua-->>ApiRestrict: { triggerResult, apiCount, threshold }
        
        alt 触发限流
            ApiRestrict->>Kafka: 发送 ApiDataDto 消息
            Kafka->>Customize: 消费消息，入库
            ApiRestrict-->>GatewayFilter: 抛出 API_RULE_TRIGGER 异常
            GatewayFilter-->>Client: 返回限流错误提示
        else 未触发
            ApiRestrict-->>GatewayFilter: 通过
        end
    else 深度规则（普通+深度同时存在）
        ApiRestrict->>ApiRestrict: 按时间窗口排序深度规则
        ApiRestrict->>Lua: apiRuleOperate(带深度规则参数)
        Lua->>Lua: 匹配当前时间所在的时间窗口
        Lua->>Lua: 按对应窗口的阈值进行限流判断
        Lua-->>ApiRestrict: { triggerResult, messageIndex, ... }
        
        alt 触发限流
            ApiRestrict->>Kafka: 发送 ApiDataDto
            ApiRestrict-->>GatewayFilter: 抛出异常（使用匹配窗口的提示信息）
            GatewayFilter-->>Client: 返回限流错误
        else 未触发
            ApiRestrict-->>GatewayFilter: 通过
        end
    end
    
    GatewayFilter->>Client: 转发请求到下游服务
```

### 4.3 API 调用记录数据流

```mermaid
sequenceDiagram
    participant Gateway as Gateway Service
    participant Kafka as Kafka 消息队列
    participant Consumer as Customize Service<br/>ApiDataMessageConsumer
    participant Service as Customize Service<br/>ApiDataService
    participant DB as MySQL
    
    Gateway->>Gateway: 触发限流规则
    Gateway->>Gateway: saveApiData() 构建 ApiDataDto
    
    Gateway->>Kafka: 发送 JSON 消息
    Note over Kafka: Topic: api_data_topic
    
    Kafka->>Consumer: 消费消息
    Consumer->>Consumer: 反序列化为 ApiData 实体
    Consumer->>Service: insert(ApiData)
    Service->>DB: INSERT INTO api_data ...
    
    Note over Gateway,DB: 查询 API 调用记录
    Admin->>Customize Service: POST /apiData/pageList (ApiDataDto)
    Customize Service->>DB: SELECT ... FROM api_data WHERE ...
    Customize Service-->>Admin: Page<ApiDataVo> 分页结果
```

### 4.4 广播调用流程

```mermaid
sequenceDiagram
    participant Admin as 管理员
    participant BroadcastCtrl as Customize Service<br/>BroadcastController
    participant BroadcastSvc as Customize Service<br/>BroadcastService
    participant ServiceBroadcast as Customize Service<br/>ServiceBroadcastCall
    participant TargetService as 目标服务实例1
    participant TargetService2 as 目标服务实例2
    
    Admin->>BroadcastCtrl: POST /broadcast/add (BroadcastCallDto)
    BroadcastCtrl->>BroadcastSvc: call(dto)
    BroadcastSvc->>ServiceBroadcast: 调用广播
    
    par 广播到所有实例
        ServiceBroadcast->>TargetService: 发送请求 (serviceName, requestBody)
        ServiceBroadcast->>TargetService2: 发送请求 (serviceName, requestBody)
    end
    
    TargetService-->>ServiceBroadcast: 响应
    TargetService2-->>ServiceBroadcast: 响应
    ServiceBroadcast-->>BroadcastSvc: 聚合结果
    BroadcastSvc-->>BroadcastCtrl: 成功
    BroadcastCtrl-->>Admin: 返回成功
```

## 5. 限流规则模型详解

### 5.1 普通规则（Rule）工作原理

普通规则采用 **滑动时间窗口** 算法：

```mermaid
graph TB
    subgraph "滑动时间窗口限流"
        direction LR
        T1[时间轴] --> T2[T-10s]
        T2 --> T3[当前时间 T]
        
        Win[统计窗口：10秒]
        Count[当前计数：N]
        Threshold[阈值：100]
        
        Win --> Count
        Count -->|N > 100| Trigger[触发限流]
        Count -->|N <= 100| Pass[通过]
        Trigger --> Block[封禁 30秒]
    end
```

**关键参数**：
- `statTime` + `statTimeType`：定义滑动窗口大小（如 10 秒）
- `threshold`：窗口内允许的最大请求数
- `effectiveTime` + `effectiveTimeType`：触发限流后的封禁时长

### 5.2 深度规则（DepthRule）工作原理

深度规则在普通规则基础上增加**时间窗口匹配**，支持**不同时间段不同限流策略**：

```mermaid
graph TB
    subgraph "时间窗口示意图"
        direction LR
        Midnight[00:00] --> Slot1[窗口1<br/>08:00-10:00<br/>阈值: 50]
        Slot1 --> Slot2[窗口2<br/>10:00-12:00<br/>阈值: 200]
        Slot2 --> Slot3[窗口3<br/>14:00-18:00<br/>阈值: 500]
        Slot3 --> End[24:00]
    end
    
    subgraph "匹配逻辑"
        CurrentTime[当前时间: 11:30]
        CurrentTime --> Match[匹配窗口2]
        Match --> UseThreshold[使用阈值: 200]
        UseThreshold --> Check[检查滑动窗口内请求数]
        Check -->|超过200| Block[触发限流]
        Check -->|未超过| Pass[通过]
    end
```

**匹配规则**：
1. 所有深度规则按 `startTimeWindow` 升序排序
2. 将时间窗口字符串（`HH:mm:ss`）转换为当天的时间戳
3. 在 Lua 脚本中通过二分法或遍历匹配当前时间所处的窗口
4. 使用匹配窗口的 `statTime`、`threshold`、`effectiveTime` 进行限流判断
5. 若没有匹配的时间窗口，则使用普通规则的阈值

### 5.3 限流模式枚举

系统包含三种限流模式，由 `ApiRuleType` 枚举定义：

| 模式 | 编码 | 说明 |
|------|------|------|
| `NO_RULE` | 0 | 无规则，不进行限流 |
| `RULE` | 1 | 普通规则模式，仅使用 Rule 进行限流 |
| `DEPTH_RULE` | 2 | 深度规则模式，Rule + DepthRule 组合限流 |

## 6. 项目结构

```
damai-server-client/damai-customize-client/
├── pom.xml                                      # 模块配置（继承 damai-server-client）
└── src/main/java/com/damai/
    ├── dto/
    │   ├── AllRuleDto.java                      # 全部规则 DTO（普通规则 + 深度规则列表）
    │   ├── ApiDataDto.java                      # API 调用记录查询参数
    │   ├── BroadcastCallDto.java                # 广播调用参数
    │   ├── DepthRuleDto.java                    # 深度规则参数
    │   ├── DepthRuleStatusDto.java              # 深度规则状态修改参数
    │   ├── DepthRuleUpdateDto.java              # 深度规则更新参数
    │   ├── RuleDto.java                         # 普通规则参数
    │   ├── RuleGetDto.java                      # 普通规则查询参数
    │   ├── RuleStatusDto.java                   # 普通规则状态修改参数
    │   └── RuleUpdateDto.java                   # 普通规则更新参数
    └── vo/
        ├── AllDepthRuleVo.java                  # 全部规则 VO
        ├── ApiDataVo.java                       # API 调用记录 VO
        ├── DepthRuleVo.java                     # 深度规则 VO
        └── RuleVo.java                          # 普通规则 VO
```

## 7. 与外部模块的交互

### 7.1 Customize Service（定制化服务）

Customize Service 是 Customize Client 数据模型的主要使用者，提供对应的 REST API 端点：

| 客户端 DTO/VO | 服务端 Controller | 服务端 Service | 说明 |
|--------------|------------------|---------------|------|
| `RuleDto` / `RuleVo` | `RuleController` | `RuleService` | 普通规则 CRUD |
| `RuleUpdateDto` | `RuleController.update()` | `RuleService.ruleUpdate()` | 更新普通规则 |
| `RuleStatusDto` | `RuleController.updateStatus()` | `RuleService.ruleUpdateStatus()` | 修改规则状态 |
| `RuleGetDto` / `RuleVo` | `RuleController.get()` | `RuleService.get()` | 查询普通规则 |
| `DepthRuleDto` / `DepthRuleVo` | `DepthRuleController` | `DepthRuleService` | 深度规则 CRUD |
| `DepthRuleUpdateDto` | `DepthRuleController.update()` | `DepthRuleService.depthRuleUpdate()` | 更新深度规则 |
| `DepthRuleStatusDto` | `DepthRuleController.updateStatus()` | `DepthRuleService.depthRuleUpdateStatus()` | 修改深度规则状态 |
| `AllRuleDto` / `AllDepthRuleVo` | `AllRuleController` | `AllRuleService` | 全部规则管理 |
| `BroadcastCallDto` | `BroadcastController.call()` | `BroadcastService` | 广播调用 |
| `ApiDataDto` / `ApiDataVo` | `ApiDataController.pageList()` | `ApiDataService` | API 调用记录分页查询 |

### 7.2 Gateway Service（网关服务）

Gateway Service 通过 Redis 间接使用 Customize Client 的 VO 对象：

| 客户端 VO | 网关服务使用方 | 用途 |
|-----------|--------------|------|
| `RuleVo` | `ApiRestrictService.apiRestrict()` | 从 Redis 读取普通规则，构建 Lua 脚本参数 |
| `DepthRuleVo` | `ApiRestrictService.apiRestrict()` | 从 Redis 读取深度规则列表，按时间窗口排序 |
| `ApiDataDto` | `ApiRestrictService.saveApiData()` | 触发限流时发送 Kafka 消息（消息体使用此类 JSON 序列化） |

### 7.3 Redis 数据共享

规则数据通过 Redis 在 Customize Service 和 Gateway Service 之间共享：

| Redis Key | 数据结构 | 值类型 | 说明 |
|-----------|---------|--------|------|
| `ALL_RULE_HASH` | Hash | Hash | 存储全部规则 |
| `ALL_RULE_HASH → RULE` | Hash Field | JSON (RuleVo) | 普通规则数据 |
| `ALL_RULE_HASH → DEPTH_RULE` | Hash Field | JSON (List<DepthRuleVo>) | 深度规则列表 |

### 7.4 Kafka 消息队列

API 调用记录通过 Kafka 异步传输：

| 组件 | 角色 | 说明 |
|------|------|------|
| Gateway Service | 生产者 | 触发限流时发送 `ApiDataDto` JSON 消息 |
| Customize Service | 消费者 | `ApiDataMessageConsumer` 消费消息并入数据库 |

## 8. 配置说明

Customize Client 模块自身不需要额外配置，它作为数据模型库被其他模块引用。

### 8.1 关联服务配置

#### Customize Service 配置
```yaml
# Customize Service 相关配置
spring:
  application:
    name: ${prefix.distinction.name:damai}-customize-service
  datasource:
    url: jdbc:mysql://localhost:3306/damai_customize?useUnicode=true&characterEncoding=utf-8
    username: root
    password: root
  redis:
    host: ${redis.host:127.0.0.1}
    port: ${redis.port:6379}
  kafka:
    bootstrap-servers: ${kafka.bootstrap-servers:127.0.0.1:9092}
    consumer:
      group-id: customize-service-group
```

#### Gateway Service 配置
```yaml
# Gateway Service 限流相关配置
gateway:
  api-restrict-paths: /api/**  # 需要进行限流的 API 路径模式
```

## 9. 与其他 Client 模块的对比

| 对比维度 | Base Data Client | Customize Client | Order Client | Program Client |
|---------|-----------------|-----------------|-------------|---------------|
| **模块类型** | Feign 客户端 | 数据模型库 | Feign 客户端 | Feign 客户端 |
| **包含 Feign 接口** | ✅ 是 | ❌ 否 | ✅ 是 | ✅ 是 |
| **包含 DTO** | ✅ 是 | ✅ 是 | ✅ 是 | ✅ 是 |
| **包含 VO** | ✅ 是 | ✅ 是 | ✅ 是 | ✅ 是 |
| **主要调用方** | Gateway Service | Customize Service / Gateway | 订单相关服务 | 节目相关服务 |
| **核心功能** | 渠道/Token/地区数据查询 | API 限流规则管理 | 订单 CRUD | 节目/场次/座位管理 |

> **注**：Customize Client 与其它 Client 模块最大的区别在于它**不直接声明 Feign 客户端接口**。它作为"纯数据模型"模块，DTO/VO 被 Customize Service 直接使用（作为 Controller 的请求体/响应体），VO 也被 Gateway Service 引用（用于反序列化 Redis 中的规则数据）。这种设计遵循了"数据模型与服务分离"的架构原则。
