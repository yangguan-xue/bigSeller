# Elasticsearch Framework 模块文档

## 1. 模块简介

**Elasticsearch Framework** 是大麦（Damai）高并发实战项目中用于封装 Elasticsearch 操作的基础框架模块。该模块基于 Spring Data Elasticsearch 和 Elasticsearch Low-Level REST Client，提供了一套简洁、统一的 API 来执行 ES 索引管理、文档增删改查、地理空间查询以及分页排序等操作。

通过该框架，业务服务（如 Program Service）无需直接处理复杂的 ES REST API 调用和 JSON 拼接，而是通过面向对象的 DTO 和工具类完成数据交互，大大降低了 Elasticsearch 的使用门槛。

---

## 2. 整体架构

### 2.1 模块依赖关系

```mermaid
graph TD
    A[damai-elasticsearch-framework] --> B[damai-common]
    A --> C[spring-boot-starter-web]
    A --> D[spring-data-elasticsearch 4.0.9.RELEASE]
    A --> E[pagehelper]
    B --> F[StringUtil]
    B --> G[其他工具类]
    
    H[damai-program-service] --> A
    I[其他业务服务] --> A
```

### 2.2 模块内部组件架构

```mermaid
graph TB
    subgraph 配置层 Config
        A[BusinessEsProperties<br/>ES配置属性] 
        B[BusinessEsAutoConfig<br/>自动配置类]
    end
    
    subgraph 数据传输层 DTO
        C[EsDataCreateDto<br/>数据创建参数]
        D[EsDataQueryDto<br/>数据查询参数]
        E[EsDocumentMappingDto<br/>文档映射定义]
        F[EsGeoPointDto<br/>地理坐标查询]
        G[EsGeoPointSortDto<br/>地理坐标排序]
    end
    
    subgraph 核心工具层 Core
        H[BusinessEsHandle<br/>ES操作核心处理类]
    end
    
    B --> A
    B --> H
    H --> C
    H --> D
    H --> E
    H --> F
    H --> G
    
    subgraph Spring SPI
        I[AutoConfiguration.imports]
    end
    
    I --> B
```

---

## 3. 核心组件详解

### 3.1 配置属性：`BusinessEsProperties`

| 属性名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `elasticsearch.ip` | `String[]` | - | ES 集群地址列表，格式：`host:port`，如 `127.0.0.1:9200` |
| `elasticsearch.userName` | `String` | - | ES 认证用户名（可选） |
| `elasticsearch.passWord` | `String` | - | ES 认证密码（可选） |
| `elasticsearch.esSwitch` | `Boolean` | `true` | ES 功能总开关，关闭后所有操作跳过 |
| `elasticsearch.esTypeSwitch` | `Boolean` | `false` | 是否启用 ES 7.x 之前的 type 支持 |
| `elasticsearch.connectTimeOut` | `Integer` | `40000` | 连接超时时间（毫秒） |
| `elasticsearch.socketTimeOut` | `Integer` | `40000` | Socket 超时时间（毫秒） |
| `elasticsearch.connectionRequestTimeOut` | `Integer` | `40000` | 连接请求超时时间（毫秒） |
| `elasticsearch.maxConnectNum` | `Integer` | `400` | 最大连接线程数 |

配置前缀：`elasticsearch`

**示例配置（application.yml）：**
```yaml
elasticsearch:
  ip: 127.0.0.1:9200
  userName: elastic
  passWord: elastic
  esSwitch: true
  esTypeSwitch: false
  connectTimeOut: 40000
  socketTimeOut: 40000
  connectionRequestTimeOut: 40000
  maxConnectNum: 400
```

### 3.2 自动配置：`BusinessEsAutoConfig`

该配置类在 `elasticsearch.ip` 属性存在时自动生效（通过 `@ConditionalOnProperty` 控制），负责：

1. **创建 `RestClient` Bean（`businessEsRestClient`）**：基于配置的 ES 地址列表创建 HTTP 连接，支持用户名/密码认证、默认请求头（Content-Type: application/json）、超时设置和 IO 线程池配置。

2. **创建 `BusinessEsHandle` Bean**：注入 `RestClient` 和配置属性，供业务服务使用。

3. **注册为 Spring Boot AutoConfiguration**：通过 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` 文件注册。

**RestClient 构建流程：**

```mermaid
flowchart TD
    A[开始] --> B[解析 elasticsearch.ip 配置]
    B --> C[将地址转换为 HttpHost 数组]
    C --> D{userName/password 是否配置?}
    D -->|是| E[设置 CredentialsProvider 认证]
    D -->|否| F[跳过认证设置]
    E --> F
    F --> G[设置默认请求头<br/>Content-Type: application/json<br/>Role: Read]
    G --> H[设置超时参数<br/>connectTimeOut / socketTimeOut<br/>/ connectionRequestTimeOut]
    H --> I[设置 IO 线程数<br/>maxConnectNum]
    I --> J[构建并返回 RestClient]
```

### 3.3 核心处理类：`BusinessEsHandle`

这是框架的核心类，封装了所有 ES 操作逻辑，通过 `RestClient`（Low-Level REST Client）直接发送 HTTP 请求到 ES 集群。

#### 3.3.1 索引管理

| 方法 | 说明 | HTTP 请求 |
|------|------|-----------|
| `createIndex(indexName, indexType, list)` | 创建索引及映射定义 | `PUT /{indexName}` |
| `checkIndex(indexName, indexType)` | 检查索引是否存在 | `GET /{indexName}/_mapping` |
| `deleteIndex(indexName)` | 删除索引 | `DELETE /{indexName}` |
| `deleteData(indexName)` | 清空索引数据（实际为删除索引） | `DELETE /{indexName}` |

**索引创建流程：**

```mermaid
flowchart LR
    A[开始创建索引] --> B{esSwitch 开启?}
    B -->|否| C[跳过]
    B -->|是| D{映射列表非空?}
    D -->|否| C
    D -->|是| E[构建 Mapping 定义]
    E --> F{text 类型?}
    F -->|是| G[添加 keyword 子字段<br/>ignore_above=256]
    F -->|否| H[直接设置字段类型]
    G --> I[设置 settings<br/>shards=1, replicas=1]
    H --> I
    I --> J[发送 PUT 请求]
    J --> K[结束]
```

**映射定义说明：**
- 对于 `text` 类型的字段，会自动添加一个 `keyword` 子字段（`ignore_above: 256`），以支持精确匹配和聚合操作。
- 默认设置 1 个分片和 1 个副本。
- `esTypeSwitch` 控制是否兼容 ES 7.x 之前的 type 概念。

#### 3.3.2 文档操作

| 方法 | 说明 | HTTP 请求 |
|------|------|-----------|
| `add(indexName, indexType, params)` | 添加文档（自动生成 ID） | `POST /{indexName}/_doc` |
| `add(indexName, indexType, params, id)` | 添加/覆盖文档（指定 ID） | `POST /{indexName}/_doc/{id}` |
| `deleteByDocumentId(index, documentId)` | 按文档 ID 删除 | `DELETE /{index}/_doc/{documentId}` |

**文档添加流程：**

```mermaid
sequenceDiagram
    participant Biz as 业务代码
    participant Handle as BusinessEsHandle
    participant ES as Elasticsearch
    
    Biz->>Handle: add("program", "program", params, id)
    Handle->>Handle: 检查 esSwitch
    Handle->>Handle: 检查 params 非空
    Handle->>Handle: params -> JSON
    Handle->>Handle: 构建 endpoint
    Note over Handle: POST /{index}/{type}<br/>或 POST /{index}/_doc<br/>+ /{id} (如果指定)
    Handle->>ES: POST 请求
    ES-->>Handle: 响应 (created / ok)
    Handle-->>Biz: true / false
```

#### 3.3.3 查询操作

**查询方法体系：**

```mermaid
flowchart TD
    A[BusinessEsHandle 查询入口] --> B{esSwitch 开启?}
    B -->|否| C[返回空列表]
    B -->|是| D[构建 SearchSourceBuilder]
    D --> E{esTypeSwitch?}
    E -->|是| F["POST /{index}/{type}/_search"]
    E -->|否| G["POST /{index}/_search"]
    F --> H[执行查询]
    G --> H
    H --> I[解析响应 JSON]
    I --> J[提取 hits.total]
    I --> K[提取 hits.hits]
    K --> L[提取 _id, _source, sort, highlight]
    L --> M[转换为目标实体类]
    M --> N[返回列表/分页结果]
```

**提供的查询方法（重载）：**

| 方法签名 | 功能 |
|----------|------|
| `query(indexName, indexType, esDataQueryDtoList, clazz)` | 基础条件查询 |
| `query(indexName, indexType, esGeoPointDto, esDataQueryDtoList, clazz)` | 带地理坐标过滤的查询 |
| `query(indexName, indexType, esDataQueryDtoList, sortParam, sortOrder, clazz)` | 带排序的查询 |
| `query(indexName, indexType, esDataQueryDtoList, geoPointDtoSortParam, sortOrder, clazz)` | 带地理坐标排序的查询 |
| `query(...)` (完整参数) | 完整参数的查询（含 searchAfter 深度分页） |
| `queryPage(indexName, indexType, esDataQueryDtoList, pageNo, pageSize, clazz)` | 基础分页查询 |
| `queryPage(...)` (多种重载) | 带排序/地理过滤的分页查询 |
| `executeQuery(...)` | 底层查询执行方法（可直接传递 SearchSourceBuilder，支持高亮） |

**查询条件构建逻辑（`getSearchSourceBuilder`）：**

```mermaid
flowchart LR
    A[EsDataQueryDto 列表] --> B{paramValue 非空?}
    B -->|是| C{paramValue 是 Collection?}
    C -->|是| D{analyse 分词?}
    C -->|否| E{analyse 分词?}
    D -->|是| F[should + matchQuery 循环]
    D -->|否| G[termsQuery 集合查询]
    E -->|是| H[matchQuery 分词匹配]
    E -->|否| I[termQuery 精确匹配]
    F --> J[BoolQuery.must]
    G --> J
    H --> J
    I --> J
    
    B -->|否| K{startTime/endTime 非空?}
    K -->|是| L[rangeQuery 范围查询]
    L --> J
    
    J --> M["sourceBuilder.query(boolQuery)"]
    M --> N[添加排序: 字段排序 / 地理排序]
    N --> O[添加地理过滤]
    O --> P[返回 SearchSourceBuilder]
```

**支持的排序类型：**
- **普通字段排序**：通过 `FieldSortBuilder` 实现，支持任意可排序字段
- **地理坐标排序**：通过 `GeoDistanceSortBuilder` 实现，按距离排序
- **自定义排序**：业务服务可通过 `executeQuery` 方法直接传递 `SearchSourceBuilder` 实现复杂排序（如随机排序）

**响应解析流程（`executeQuery`）：**

```mermaid
flowchart TD
    A[收到 ES 响应 JSON] --> B[解析 hits 对象]
    B --> C{esTypeSwitch?}
    C -->|是| D[total 直接取值]
    C -->|否| E[total 取 value 字段]
    D --> F{分页对象非空?}
    E --> F
    F -->|是| G[设置 total 到 PageInfo]
    F -->|否| H[跳过]
    G --> I[遍历 hits.hits 数组]
    H --> I
    I --> J[提取 _id]
    I --> K[提取 _source]
    I --> L[提取 sort 数组]
    L --> M{sort 非空?}
    M -->|是| N[将 sort 值放入_source 中]
    M -->|否| O[跳过]
    K --> P{有高亮字段?}
    P -->|是| Q[提取高亮内容替换_source]
    P -->|否| R[跳过]
    Q --> S[ES_ID 非空?]
    R --> S
    S -->|是| T[将 esId 放入_source]
    S -->|否| U[跳过]
    T --> V[JSON -> 目标类型]
    U --> V
    V --> W[加入结果列表]
    W --> X[返回结果]
```

### 3.4 数据传输对象（DTO）

#### `EsDataCreateDto`（数据创建参数）

| 字段 | 类型 | 说明 |
|------|------|------|
| `paramName` | `String` | 字段名 |
| `paramValue` | `Object` | 字段值 |

#### `EsDataQueryDto`（查询参数）

| 字段 | 类型 | 说明 |
|------|------|------|
| `paramName` | `String` | 字段名 |
| `paramValue` | `Object` | 字段值 |
| `startTime` | `Date` | 时间范围开始（时间字段专用） |
| `endTime` | `Date` | 时间范围结束（时间字段专用） |
| `analyse` | `boolean` | 是否分词查询（默认 `false`，即精确匹配） |

#### `EsDocumentMappingDto`（文档映射定义）

| 字段 | 类型 | 说明 |
|------|------|------|
| `paramName` | `String` | 字段名 |
| `paramType` | `String` | ES 字段类型（如 `text`, `keyword`, `long`, `date` 等） |

#### `EsGeoPointDto`（地理坐标查询）

| 字段 | 类型 | 说明 |
|------|------|------|
| `paramName` | `String` | 字段名（存储地理坐标的字段） |
| `latitude` | `BigDecimal` | 纬度 |
| `longitude` | `BigDecimal` | 经度 |

#### `EsGeoPointSortDto`（地理坐标排序）

| 字段 | 类型 | 说明 |
|------|------|------|
| `paramName` | `String` | 字段名 |
| `latitude` | `BigDecimal` | 纬度 |
| `longitude` | `BigDecimal` | 经度 |

---

## 4. 业务集成示例（Program Service）

### 4.1 ProgramEs 类的依赖注入

```java
@Component
public class ProgramEs {
    
    @Autowired
    private BusinessEsHandle businessEsHandle;
    
    // ... 业务查询方法
}
```

### 4.2 索引命名规则

索引名称格式：`{应用前缀}-{索引名}`

例如 Program Service 中：
```java
// 索引名: damai-program (默认前缀)
SpringUtil.getPrefixDistinctionName() + "-" + ProgramDocumentParamName.INDEX_NAME
```

其中 `ProgramDocumentParamName.INDEX_NAME = "program"`，应用前缀默认为 `damai`。

### 4.3 业务查询方法详解

#### 首页列表查询（`selectHomeList`）

```mermaid
sequenceDiagram
    participant C as Controller
    participant PEs as ProgramEs
    participant H as BusinessEsHandle
    participant ES as Elasticsearch
    
    C->>PEs: selectHomeList(dto)
    loop 遍历 parentProgramCategoryIds
        PEs->>PEs: 构建 EsDataQueryDto 列表
        Note over PEs: areaId / prime<br/>parentProgramCategoryId
        PEs->>H: queryPage(index, type, dtoList, 1, 7, ProgramListVo.class)
        H->>ES: POST /damai-program/_search
        ES-->>H: 返回结果
        H-->>PEs: PageInfo<ProgramListVo>
        PEs->>PEs: 包装为 ProgramHomeVo
    end
    PEs-->>C: List<ProgramHomeVo>
```

#### 推荐列表查询（`recommendList`）

使用 `executeQuery` 直接传递 `SearchSourceBuilder`，通过脚本排序实现随机推荐：

```java
Script script = new Script("Math.random()");
ScriptSortBuilder scriptSortBuilder = new ScriptSortBuilder(script, ScriptSortBuilder.ScriptSortType.NUMBER);
scriptSortBuilder.order(SortOrder.ASC);
searchSourceBuilder.sort(scriptSortBuilder);

businessEsHandle.executeQuery(index, type, list, null, ProgramListVo.class, searchSourceBuilder, null);
```

#### 分页列表查询（`selectPage`）

支持多种排序策略：

| 类型值 | 排序字段 | 排序方向 | 说明 |
|--------|----------|----------|------|
| 2 | `high_heat` | DESC | 按热度降序（推荐排序） |
| 3 | `showTime` | ASC | 按开场时间升序（最近开场） |
| 4 | `issueTime` | ASC | 按上架时间升序（最新上架） |
| default | - | - | 相关度排序（ES 默认 _score） |

#### 搜索查询（`search`）

```mermaid
flowchart TD
    A[搜索请求] --> B[构建 BoolQuery]
    B --> C{areaId 非空?}
    C -->|是| D[termQuery 地区过滤]
    C -->|否| E[跳过]
    D --> F{parentProgramCategoryId 非空?}
    E --> F
    F -->|是| G[termQuery 分类过滤]
    F -->|否| H[跳过]
    G --> I{showDayTime 范围?}
    H --> I
    I -->|是| J[rangeQuery 时间范围]
    I -->|否| K[跳过]
    J --> L{搜索内容非空?}
    K --> L
    L -->|是| M[构建 should 查询]
    M --> N[matchQuery title]
    M --> O[matchQuery actor]
    N --> P[boolQuery.minimumShouldMatch=1]
    O --> P
    P --> Q[设置排序]
    L -->|否| Q
    Q --> R[设置分页 from/size]
    R --> S[设置高亮<br/>title, actor 字段<br/><em>标签]
    S --> T[executeQuery 执行]
    T --> U[解析高亮结果]
    U --> V[返回分页数据]
```

### 4.4 Program 索引字段映射

| 字段名 | ES 类型 | 说明 |
|--------|---------|------|
| `id` | long | 节目 ID |
| `programGroupId` | long | 节目组 ID |
| `prime` | int | 是否为精选 |
| `title` | text + keyword | 标题（支持分词搜索） |
| `actor` | text + keyword | 演员（支持分词搜索） |
| `place` | text + keyword | 场地 |
| `itemPicture` | keyword | 图片 URL |
| `areaId` | long | 地区 ID |
| `areaName` | keyword | 地区名称 |
| `programCategoryId` | long | 节目分类 ID |
| `programCategoryName` | keyword | 节目分类名称 |
| `parentProgramCategoryId` | long | 父节目分类 ID |
| `parentProgramCategoryName` | keyword | 父节目分类名称 |
| `high_heat` | long | 热度 |
| `issueTime` | date | 上架时间 |
| `showTime` | date | 开场时间 |
| `showDayTime` | date | 演出日期 |
| `showWeekTime` | keyword | 演出星期 |
| `minPrice` | decimal | 最低票价 |
| `maxPrice` | decimal | 最高票价 |

---

## 5. 数据流与交互流程

### 5.1 索引创建流程

```mermaid
sequenceDiagram
    participant Biz as 业务服务
    participant Handle as BusinessEsHandle
    participant ES as Elasticsearch
    participant Config as BusinessEsAutoConfig
    
    Config->>Handle: 初始化 (注入 RestClient)
    
    Biz->>Handle: createIndex("program", "program", mappings)
    Handle->>Handle: 检查 esSwitch
    Handle->>Handle: 构建 XContentBuilder
    Note over Handle: 遍历 mappings, 设置字段类型<br/>text 类型自动添加 keyword 子字段
    Handle->>Handle: 设置 settings (shards=1, replicas=1)
    Handle->>ES: PUT /program
    Note over Handle: 请求体为 JSON mapping
    ES-->>Handle: 返回响应
    Handle-->>Biz: 完成
```

### 5.2 数据添加流程

```mermaid
sequenceDiagram
    participant Biz as 业务服务
    participant Handle as BusinessEsHandle
    participant ES as Elasticsearch
    
    Biz->>Handle: add("program", "program", params, id)
    Handle->>Handle: 检查 esSwitch
    Handle->>Handle: 检查 params 非空
    Handle->>Handle: params -> JSON
    Handle->>Handle: 构建 endpoint
    Note over Handle: POST /{index}/{type}<br/>或 POST /{index}/_doc<br/>+ /{id} (如果指定)
    Handle->>ES: POST 请求
    ES-->>Handle: 响应 (created / ok)
    Handle-->>Biz: true / false
```

### 5.3 数据查询流程

```mermaid
sequenceDiagram
    participant Controller as 控制器
    participant Service as 业务服务
    participant ESHandle as BusinessEsHandle
    participant ES as Elasticsearch
    
    Controller->>Service: 查询请求
    Service->>Service: 构建 EsDataQueryDto 列表
    Service->>ESHandle: queryPage(indexName, indexType, dtoList, sort, order, pageNo, pageSize, clazz)
    ESHandle->>ESHandle: 构建 SearchSourceBuilder
    Note over ESHandle: 遍历 dtoList<br/>生成 termQuery / matchQuery / rangeQuery
    ESHandle->>ESHandle: 设置 from / size / sort
    ESHandle->>ES: POST /{index}/_search
    ES-->>ESHandle: 返回 JSON
    ESHandle->>ESHandle: 解析结果
    Note over ESHandle: 提取 _id, _source, sort<br/>JSON -> 目标类
    ESHandle-->>Service: PageInfo<T>
    Service-->>Controller: 返回响应
```

### 5.4 搜索高亮流程

```mermaid
sequenceDiagram
    participant C as Controller
    participant PEs as ProgramEs
    participant H as BusinessEsHandle
    participant ES as Elasticsearch
    
    C->>PEs: search(searchDto)
    PEs->>PEs: 构建 BoolQueryBuilder
    Note over PEs: termQuery(areaId)<br/>termQuery(parentProgramCategoryId)<br/>rangeQuery(showDayTime)<br/>matchQuery(title) / matchQuery(actor)
    PEs->>PEs: 构建 HighlightBuilder
    Note over PEs: title 和 actor 字段<br/>preTags="<em>"<br/>postTags="</em>"
    PEs->>PEs: 构建 SearchSourceBuilder + 排序
    PEs->>H: executeQuery(index, type, list, pageInfo, clazz, sourceBuilder, highLightFields)
    H->>ES: POST /{index}/_search
    ES-->>H: 返回高亮结果
    H->>H: 解析 highlight 字段
    Note over H: 用高亮内容替换原始字段
    H-->>PEs: 填充 list 和 pageInfo
    PEs-->>C: PageVo<ProgramListVo>
```

---

## 6. 与其他模块的关联

| 相关模块 | 关联说明 |
|----------|----------|
| [damai-common](Common.md) | 提供 `StringUtil` 工具类，用于字符串判空等基础操作 |
| [damai-program-service](Program%20Service.md) | 主要使用者，通过 `ProgramEs` 使用 ES 进行节目搜索和列表展示 |
| [damai-spring-cloud-framework](Spring%20Cloud%20Framework.md) | 提供 `SpringUtil.getPrefixDistinctionName()` 用于动态获取索引前缀 |
| [damai-redis-tool-framework](Redis%20Tool%20Framework.md) | 配合 Redis 缓存，形成"ES 搜索 + Redis 缓存"的多级数据查询方案 |
| [damai-thread-pool-framework](Thread%20Pool%20Framework.md) | 可配合异步线程池执行 ES 数据同步任务 |

---

## 7. 设计亮点与最佳实践

### 7.1 开关控制
- **`esSwitch` 全局开关**：方便在开发/测试环境关闭 ES 功能，不影响业务代码逻辑，所有操作方法都会先检查此开关
- **`esTypeSwitch` 类型兼容开关**：支持 ES 6.x 到 7.x+ 的平滑迁移，为 true 时使用 `{index}/{type}` 路径格式

### 7.2 查询构建模式
- 基于 `BoolQueryBuilder` 的 must 组合查询，支持精确匹配（termQuery）、分词匹配（matchQuery）、集合匹配（termsQuery）和时间范围查询（rangeQuery）
- 统一通过 `EsDataQueryDto` 传递参数，避免业务代码直接拼接 ES DSL
- 灵活的 `analyse` 标记控制是否分词查询

### 7.3 地理空间支持
- 内置 `GeoDistanceQueryBuilder` 用于地理坐标过滤（支持超远距离查询）
- 内置 `GeoDistanceSortBuilder` 用于按距离排序（支持米单位）
- 适用于 LBS（基于位置的服务）场景，如"附近演出"等

### 7.4 分页与排序
- 支持 `from + size` 传统分页
- 支持 `searchAfter` 深度分页（通过完整参数方法传递 `searchAfterSort` 数组）
- 多种排序策略：字段排序、地理距离排序、脚本排序（如随机排序）
- `trackTotalHits(true)` 确保精确的总记录数统计

### 7.5 高亮搜索
- 支持搜索结果高亮，`executeQuery` 方法自动解析 `highlight` 字段并替换到返回对象中
- 通过 `preTags` 和 `postTags` 自定义高亮标签

### 7.6 自动映射
- `text` 类型字段自动添加 `keyword` 子字段，兼顾分词搜索和精确匹配
- 返回结果中自动注入 `_id` 为 `esId` 字段，`sort` 值为 `sort` 字段，方便业务使用

---

## 8. 注意事项

1. **索引命名**：业务服务应使用唯一的索引名称前缀（通过 `SpringUtil.getPrefixDistinctionName()` 获取），避免多环境数据冲突
2. **分页限制**：`from + size` 分页在深度分页时性能会下降，建议限制最大分页深度或使用 `searchAfter`
3. **`esTypeSwitch`**：ES 7.x 已废弃 type 概念，新建项目建议关闭此开关（设为 `false`）
4. **text 类型字段**：自动添加的 `keyword` 子字段适用于精确匹配和聚合，但 `ignore_above=256` 表示超过 256 字符的文本会被忽略
5. **空值处理**：查询时 `paramValue` 为 `null` 的条件会被跳过，不会加入查询条件
6. **线程安全**：`RestClient` 是线程安全的，可以在多个线程间共享使用
7. **依赖版本**：当前使用 `spring-data-elasticsearch 4.0.9.RELEASE`，对应 ES 7.x 版本

---

## 9. 附录：核心 API 速查表

### 索引管理

```java
// 创建索引
void createIndex(String indexName, String indexType, List<EsDocumentMappingDto> list)

// 检查索引
boolean checkIndex(String indexName, String indexType)

// 删除索引
boolean deleteIndex(String indexName)

// 清空数据
void deleteData(String indexName)
```

### 文档操作

```java
// 添加文档（自动ID）
boolean add(String indexName, String indexType, Map<String,Object> params)

// 添加文档（指定ID）
boolean add(String indexName, String indexType, Map<String,Object> params, String id)

// 按文档ID删除
void deleteByDocumentId(String index, String documentId)
```

### 查询操作

```java
// 基础查询
List<T> query(String indexName, String indexType, List<EsDataQueryDto> list, Class<T> clazz)

// 带地理过滤查询
List<T> query(String indexName, String indexType, EsGeoPointDto geoPointDto, List<EsDataQueryDto> list, Class<T> clazz)

// 带排序查询
List<T> query(String indexName, String indexType, List<EsDataQueryDto> list, String sortParam, SortOrder sortOrder, Class<T> clazz)

// 基础分页查询
PageInfo<T> queryPage(String indexName, String indexType, List<EsDataQueryDto> list, Integer pageNo, Integer pageSize, Class<T> clazz)

// 带排序分页查询
PageInfo<T> queryPage(String indexName, String indexType, List<EsDataQueryDto> list, String sortParam, SortOrder sortOrder, Integer pageNo, Integer pageSize, Class<T> clazz)

// 底层执行查询（支持自定义 SearchSourceBuilder 和高亮）
void executeQuery(String indexName, String indexType, List<T> list, PageInfo<T> pageInfo, Class<T> clazz, SearchSourceBuilder sourceBuilder, List<String> highLightFieldNameList)
```
