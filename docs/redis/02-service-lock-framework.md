# @ServiceLock 分布式锁框架 — 逐行详解

> 模块路径: `damai/damai-redisson-framework/damai-redisson-service-framework/damai-service-lock-framework/`
>
> 依赖前置: `damai-redisson-common-framework/`（提供 RedissonClient、LockInfoHandle 基类、LocalLockCache）

---

## 一、整体架构

### 1.1 模块依赖关系

```
damai-service-lock-framework  (当前模块)
    ├── 依赖 damai-redisson-common-framework
    │       ├── RedissonClient（由 RedissonCommonAutoConfiguration 创建）
    │       ├── LockInfoHandle / AbstractLockInfoHandle（SpEL 锁 key 解析基类）
    │       ├── LockInfoHandleFactory（工厂，根据类型获取 LockInfoHandle 实现）
    │       └── LocalLockCache（Caffeine 本地锁缓存，供幂等模块使用）
    └── 自身提供
            ├── @ServiceLock 注解
            ├── ServiceLockAspect（AOP 切面）
            ├── ServiceLocker 接口 + 4 种实现（可重入/公平/读/写）
            ├── ServiceLockFactory / ManageLocker（锁工厂）
            └── ServiceLockTool（编程式锁工具）
```

### 1.2 两条使用路径

```
路径 A：声明式（注解）
    Controller/Service 方法上加 @ServiceLock
        → Spring AOP 拦截 @Around("@annotation(servicelock)")
        → ServiceLockAspect.around()
        → LockInfoHandleFactory 获取 ServiceLockInfoHandle
        → AbstractLockInfoHandle 解析 SpEL key
        → ServiceLockFactory 根据 LockType 获取对应 ServiceLocker
        → Redisson RLock.tryLock()
        → 执行业务 → finally unlock

路径 B：编程式
    @Autowired ServiceLockTool
        → serviceLockTool.execute(taskRun, name, keys)
        → 或 serviceLockTool.submit(taskCall, name, keys)
        → 内部走相同链路：LockInfoHandle → ServiceLockFactory → RLock
```

### 1.3 完整调用链路（数据流）

```
┌─────────────────────────────────────────────────────────┐
│ 用户代码 @ServiceLock(name="pay", keys={"#orderId"})    │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│ ServiceLockAspect.around()                              │
│  1. lockInfoHandleFactory.getLockInfoHandle("service_lock") │
│     → 获取 ServiceLockInfoHandle 实例（Spring Bean）     │
│  2. lockInfoHandle.getLockName(joinPoint, name, keys)   │
│     → AbstractLockInfoHandle 解析 SpEL                   │
│     → 最终锁名: "服务名-SERVICE_LOCK:pay:E10086"         │
│  3. serviceLockFactory.getLock(LockType.Reentrant)      │
│     → ManageLocker.getReentrantLocker()                 │
│     → new RedissonReentrantLocker(redissonClient)       │
│  4. lock.tryLock(lockName, SECONDS, waitTime)           │
│     → redissonClient.getLock(lockName).tryLock(...)     │
│  5. 获取锁成功 → joinPoint.proceed()                    │
│  6. finally → lock.unlock(lockName)                     │
└─────────────────────────────────────────────────────────┘
```

---

## 二、逐文件详解

### 2.1 基础支撑：RedissonClient 创建

#### RedissonCommonAutoConfiguration.java

```java
@AutoConfigureBefore(value = {RedissonAutoConfigurationV2.class, RedissonAutoConfiguration.class})
@EnableConfigurationProperties(RedissonBaseProperties.class)
public class RedissonCommonAutoConfiguration {

    private final AtomicInteger executeTaskThreadCount = new AtomicInteger(1);

    @Bean
    public RedissonClient redissonClient(RedisProperties redisProperties, RedissonBaseProperties redissonBaseProperties) {
        Config config = new Config();

        // 判断是否启用 SSL → 决定 redis:// 还是 rediss:// 前缀
        String prefix = "redis://";
        Method method = ReflectionUtils.findMethod(RedisProperties.class, "isSsl");
        if (method != null && (Boolean) ReflectionUtils.invokeMethod(method, redisProperties)) {
            prefix = "rediss://";
        }

        config.useSingleServer()
                .setAddress(prefix + redisProperties.getHost() + ":" + redisProperties.getPort())
                .setConnectTimeout(1000)
                .setDatabase(redisProperties.getDatabase())
                .setPassword(redisProperties.getPassword());

        // 设置 Redisson 默认线程数
        config.setThreads(redissonBaseProperties.getThreads());         // 默认 16
        config.setNettyThreads(redissonBaseProperties.getNettyThreads()); // 默认 32

        // 如果配置了线程池参数，则创建自定义线程池供 Redisson 内部使用
        if (Objects.nonNull(redissonBaseProperties.getCorePoolSize()) &&
                Objects.nonNull(redissonBaseProperties.getMaximumPoolSize())) {
            ThreadPoolExecutor threadPoolExecutor = new ThreadPoolExecutor(
                    redissonBaseProperties.getCorePoolSize(),
                    redissonBaseProperties.getMaximumPoolSize(),
                    redissonBaseProperties.getKeepAliveTime(),
                    redissonBaseProperties.getUnit(),
                    new LinkedBlockingQueue<>(redissonBaseProperties.getWorkQueueSize()),
                    r -> new Thread(Thread.currentThread().getThreadGroup(), r,
                            "redisson-thread-" + executeTaskThreadCount.getAndIncrement()));
            config.setExecutor(threadPoolExecutor);
        }

        return Redisson.create(config);
    }
    // ...
}
```

**逐行拆解：**

| 行 | 代码 | 作用 |
|----|------|------|
| 1 | `@AutoConfigureBefore(...)` | 保证本项目 RedissonClient 配置**优先于** Redisson 官方自动配置（v2 或 v3 版本），覆盖默认行为 |
| 7 | `AtomicInteger executeTaskThreadCount` | 线程池命名计数器，确保线程名唯一 |
| 9 | `RedissonClient redissonClient(...)` | 方法参数 `RedisProperties` 来自 `spring-boot-starter-data-redis`（自动绑定 application.yml 的 `spring.redis.*`），`RedissonBaseProperties` 绑定 `spring.redis.redisson.*` |
| 11 | `ReflectionUtils.findMethod` | ↓ |
| 12 | `ReflectionUtils.invokeMethod` | 通过反射调用 `RedisProperties.isSsl()`，避免编译期版本依赖问题（Spring Boot 2.x 没这个方法 → 反射返回 null → 走 redis://） |
| 15 | `config.useSingleServer()` | 单节点模式。生产环境可改为 `useClusterServers()` 或 `useSentinelServers()` |
| 26 | `config.setThreads()` | Redisson 业务处理线程数（实际不是 Netty 的 IO 线程，是执行 Lua 脚本和监听器的线程） |
| 30-40 | 自定义线程池 | 默认不创建（corePoolSize 默认为 null），仅在用户配置了才启用 |

**为什么 @AutoConfigureBefore 官方配置？**

因为 `redisson-spring-boot-starter` 也会自动创建 `RedissonClient`。本项目要先于它创建，覆盖 Redisson 的默认配置（比如自定义线程池）。

---

#### RedissonBaseProperties.java

```java
@ConfigurationProperties(prefix = "spring.redis.redisson")
public class RedissonBaseProperties {
    private Integer threads = 16;           // Redisson 业务线程数
    private Integer nettyThreads = 32;       // Netty IO 线程数
    private Integer corePoolSize = null;     // 自定义线程池核心数（null 表示不启用）
    private Integer maximumPoolSize = null;  // 最大线程数
    private long keepAliveTime = 30;         // 空闲线程存活时间
    private TimeUnit unit = TimeUnit.SECONDS;
    private Integer workQueueSize = 256;     // 工作队列大小
}
```

对应的 application.yml 配置：
```yaml
spring:
  redis:
    redisson:
      threads: 16
      netty-threads: 32
```

---

### 2.2 锁 Key 构建体系

这是整个锁框架最精妙的部分——用 **SpEL（Spring Expression Language）** 动态解析锁 Key。

#### LockInfoHandle.java（接口）

```java
public interface LockInfoHandle {
    // 用于 AOP 切面：从 JoinPoint 中解析方法参数，构建锁名
    String getLockName(JoinPoint joinPoint, String name, String[] keys);

    // 用于编程式：直接拼接字符串，不需要 JoinPoint
    String simpleGetLockName(String name, String[] keys);
}
```

两个方法的区别：
- `getLockName`：用于 AOP 场景，能从 `JoinPoint` 拿到方法参数值，解析 SpEL
- `simpleGetLockName`：用于编程式场景，传入的是最终字符串，直接拼接

#### AbstractLockInfoHandle.java（抽象基类）

```java
public abstract class AbstractLockInfoHandle implements LockInfoHandle {

    private static final String LOCK_DISTRIBUTE_ID_NAME_PREFIX = "LOCK_DISTRIBUTE_ID";
    // 参数名发现器：从方法字节码中获取参数名（比如 SpEL 中的 #userId 需要知道参数名叫 userId）
    private final ParameterNameDiscoverer nameDiscoverer = new ExtParameterNameDiscoverer();
    // SpEL 表达式解析器
    private final ExpressionParser parser = new SpelExpressionParser();

    // 子类实现：返回锁前缀名，比如 "SERVICE_LOCK" 或 "REPEAT_EXECUTE_LIMIT"
    protected abstract String getLockPrefixName();
```

**为什么需要 ParameterNameDiscoverer？**

当在注解中写 `keys={"#userId"}` 时，SpEL 需要知道方法参数名叫 `userId`。Java 编译后默认不保留参数名（变成 arg0, arg1），所以需要从 LocalVariableTable 属性中读取。`ExtParameterNameDiscoverer` 就是为此而生（后面详述）。

```java
    @Override
    public String getLockName(JoinPoint joinPoint, String name, String[] keys) {
        return SpringUtil.getPrefixDistinctionName()        // 服务名前缀（如 "damai-order-service"）
                + "-" + getLockPrefixName()                  // 锁类型前缀（如 "SERVICE_LOCK"）
                + SEPARATOR + name                           // 业务名（如 "pay"）
                + getRelKey(joinPoint, keys);                // SpEL 解析后的 key 参数
                // 最终结果: "damai-order-service-SERVICE_LOCK:pay:E10086"
    }
```

| 段 | 示例 | 来源 |
|----|------|------|
| 服务前缀 | `damai-order-service` | `SpringUtil.getPrefixDistinctionName()` → 从 application.yml 读取 `distinction.name` |
| 锁类型 | `SERVICE_LOCK` | 子类 `ServiceLockInfoHandle.getLockPrefixName()` |
| 业务名 | `pay` | `@ServiceLock(name="pay")` |
| 动态 key | `E10086` | `keys={"#orderId"}` → SpEL 解析为方法参数 `orderId` 的值 |

**为什么加服务前缀？**

不同服务可能有相同业务名的锁，加上服务名可避免跨服务锁冲突。

```java
    @Override
    public String simpleGetLockName(String name, String[] keys) {
        // 编程式场景：直接拼接，不做 SpEL 解析
        List<String> definitionKeyList = new ArrayList<>();
        for (String key : keys) {
            if (StringUtil.isNotEmpty(key)) definitionKeyList.add(key);
        }
        return SpringUtil.getPrefixDistinctionName() + "-"
                + LOCK_DISTRIBUTE_ID_NAME_PREFIX + SEPARATOR
                + name + SEPARATOR + String.join(SEPARATOR, definitionKeyList);
        // 结果: "damai-order-service-LOCK_DISTRIBUTE_ID:pay:E10086"
    }
```

注意 `simpleGetLockName` 用的前缀是 `LOCK_DISTRIBUTE_ID` 而不是 `SERVICE_LOCK`，这是为了与注解方式区分。

```java
    // 核心方法：SpEL 解析
    private String getRelKey(JoinPoint joinPoint, String[] keys) {
        Method method = getMethod(joinPoint);     // 获取目标方法（反射）
        List<String> definitionKeys = getSpElKey(keys, method, joinPoint.getArgs());
        return SEPARATOR + String.join(SEPARATOR, definitionKeys);
    }

    private Method getMethod(JoinPoint joinPoint) {
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Method method = signature.getMethod();
        // 如果方法是接口方法，需要获取实现类的实际方法（否则无法获取参数名）
        if (method.getDeclaringClass().isInterface()) {
            try {
                method = joinPoint.getTarget().getClass()
                    .getDeclaredMethod(signature.getName(), method.getParameterTypes());
            } catch (Exception e) { log.error("get method error ", e); }
        }
        return method;
    }

    private List<String> getSpElKey(String[] definitionKeys, Method method, Object[] parameterValues) {
        List<String> definitionKeyList = new ArrayList<>();
        for (String definitionKey : definitionKeys) {
            if (!ObjectUtils.isEmpty(definitionKey)) {
                // 创建 SpEL 评估上下文：绑定方法参数名和参数值
                EvaluationContext context = new MethodBasedEvaluationContext(
                    null, method, parameterValues, nameDiscoverer);
                // 解析表达式，比如 "#orderId" → 获取参数 orderId 的值
                Object objKey = parser.parseExpression(definitionKey).getValue(context);
                definitionKeyList.add(ObjectUtils.nullSafeToString(objKey));
            }
        }
        return definitionKeyList;
    }
```

**关键行详解（getSpElKey）：**

- `MethodBasedEvaluationContext`：Spring 提供的 SpEL 上下文，自动将方法参数名绑定为变量。例如方法签名 `createOrder(String orderId, Long userId)`，则在 SpEL 中可直接使用 `#orderId` 引用。
- `nameDiscoverer`：自定义的 `ExtParameterNameDiscoverer`，它的职责是从字节码中读取 `LocalVariableTable` 属性得到参数名（因为 Java 反射默认只能拿到 `arg0, arg1`）。
- `parser.parseExpression(definitionKey).getValue(context)`：将字符串 `"#orderId"` 解析为 SpEL 表达式树，然后在上下文中求值，得到 `orderId` 参数的**实际值**。

**假设场景：**

```java
// 方法定义
public String createOrder(String orderId, Long userId) {
    // ...
}

// 注解
@ServiceLock(name="create", keys={"#orderId", "#userId"})
```

执行流程：
1. `definitionKeys` = `["#orderId", "#userId"]`
2. `getSpElKey` 遍历数组
3. 第一次：解析 `#orderId` → 从方法参数中取第一个参数（`parameterValues[0]`）→ 得到 `"ORD20240523001"`
4. 第二次：解析 `#userId` → 取第二个参数 → 得到 `"10086"`
5. 最终锁名：`"damai-order-service-SERVICE_LOCK:create:ORD20240523001:10086"`

#### ServiceLockInfoHandle.java

```java
public class ServiceLockInfoHandle extends AbstractLockInfoHandle {
    private static final String LOCK_PREFIX_NAME = "SERVICE_LOCK";
    @Override
    protected String getLockPrefixName() { return LOCK_PREFIX_NAME; }
}
```

极其简洁——只定义了锁前缀名。所有复杂逻辑都在父类 `AbstractLockInfoHandle` 中。这就是**模板方法模式**：父类定义骨架（如何构建锁名），子类只提供个性化信息（前缀名）。

#### LockInfoHandleFactory.java

```java
public class LockInfoHandleFactory implements ApplicationContextAware {
    private ApplicationContext applicationContext;

    // 根据 bean name 获取对应的 LockInfoHandle
    public LockInfoHandle getLockInfoHandle(String lockInfoType) {
        return applicationContext.getBean(lockInfoType, LockInfoHandle.class);
    }

    @Override
    public void setApplicationContext(ApplicationContext applicationContext) throws BeansException {
        this.applicationContext = applicationContext;
    }
}
```

**为什么用 ApplicationContextAware 而不是 @Autowired？**

因为 `LockInfoHandleFactory` 不是在 Spring 管理的 Bean 中通过 `@Autowired` 注入的，它是在 `RedissonCommonAutoConfiguration` 中用 `new` 创建的。所以需要实现 `ApplicationContextAware` 手动获取容器引用。

### 2.3 锁类型枚举与锁实现

#### LockType.java

```java
public enum LockType {
    Reentrant,  // 可重入锁（默认）
    Fair,       // 公平锁
    Read,       // 读锁
    Write;      // 写锁
}
```

#### ServiceLocker.java（锁接口）

```java
public interface ServiceLocker {
    RLock getLock(String lockKey);                              // 获取锁对象（不自动加锁）
    RLock lock(String lockKey);                                 // 阻塞式加锁（一直等到获取为止）
    RLock lock(String lockKey, long leaseTime);                 // 加锁并指定持有时间（秒）
    RLock lock(String lockKey, TimeUnit unit, long leaseTime);  // 加锁并指定持有时间（自定义单位）
    boolean tryLock(String lockKey, TimeUnit unit, long waitTime);  // 尝试加锁，等待 waitTime 后放弃
    boolean tryLock(String lockKey, TimeUnit unit, long waitTime, long leaseTime); // 尝试+超时+持有时间
    void unlock(String lockKey);       // 根据 key 解锁
    void unlock(RLock lock);           // 根据锁对象解锁
}
```

**接口设计要点：**
- 提供 `lock()` 和 `tryLock()` 两种模式：`lock` 阻塞，`tryLock` 非阻塞（有超时）
- `leaseTime`：锁的自动释放时间（Redisson 默认 30 秒 + WatchDog 自动续期）
- 两个 `unlock` 重载：传 key 的方式内部会再调一次 `getLock`，性能略差于传 RLock

#### RedissonReentrantLocker.java（可重入锁实现）

```java
@AllArgsConstructor
public class RedissonReentrantLocker implements ServiceLocker {
    private final RedissonClient redissonClient;

    @Override
    public RLock getLock(String lockKey) {
        return redissonClient.getLock(lockKey);              // Redisson 可重入锁
    }

    @Override
    public RLock lock(String lockKey) {
        RLock lock = redissonClient.getLock(lockKey);
        lock.lock();                                          // 阻塞直到获取锁
        return lock;
    }

    @Override
    public boolean tryLock(String lockKey, TimeUnit unit, long waitTime) {
        RLock lock = redissonClient.getLock(lockKey);
        try {
            return lock.tryLock(waitTime, unit);              // 等待 waitTime 毫秒/秒
        } catch (InterruptedException e) {
            return false;                                     // 被中断返回 false
        }
    }

    @Override
    public boolean tryLock(String lockKey, TimeUnit unit, long waitTime, long leaseTime) {
        RLock lock = redissonClient.getLock(lockKey);
        try {
            return lock.tryLock(waitTime, leaseTime, unit);   // 最完整的 tryLock 签名
        } catch (InterruptedException e) {
            return false;
        }
    }

    @Override
    public void unlock(String lockKey) {
        redissonClient.getLock(lockKey).unlock();
    }

    @Override
    public void unlock(RLock lock) {
        lock.unlock();
    }
}
```

#### 四种锁实现的对比

| 实现类 | Redisson API | 锁特性 |
|--------|-------------|--------|
| `RedissonReentrantLocker` | `getLock(key)` | 可重入（同一线程可多次加锁）、非公平、默认 30s WatchDog |
| `RedissonFairLocker` | `getFairLock(key)` | 可重入 + 公平（按请求顺序排队，基于 Redis List 实现） |
| `RedissonReadLocker` | `getReadWriteLock(key).readLock()` | 读读不互斥、读写互斥、写写互斥 |
| `RedissonWriteLocker` | `getReadWriteLock(key).writeLock()` | 写写互斥、读写互斥 |

**可重入锁**和**公平锁**的区别（八股考点）：

| 特性 | ReentrantLock | FairLock |
|------|---------------|----------|
| 默认策略 | 非公平（抢占式） | 公平（FIFO 排队） |
| 性能 | 高（无需上下文切换） | 低（需要维护队列） |
| 适用场景 | 高并发、允许偶尔"插队" | 严格按顺序执行 |
| Redisson 实现 | `getLock()` | `getFairLock()` |

**ReadWriteLock 的核心规则（八股考点）：**
- 读锁不阻塞读锁：多个线程可以同时读
- 写锁阻塞读锁和写锁：写操作必须是独占的
- 适用于读多写少场景

#### ManageLocker.java（锁管理）

```java
public class ManageLocker {
    // 缓存所有锁类型实现，避免每次 new
    private final Map<LockType, ServiceLocker> cacheLocker = new HashMap<>();

    public ManageLocker(RedissonClient redissonClient) {
        cacheLocker.put(Reentrant, new RedissonReentrantLocker(redissonClient));
        cacheLocker.put(Fair, new RedissonFairLocker(redissonClient));
        cacheLocker.put(Write, new RedissonWriteLocker(redissonClient));
        cacheLocker.put(Read, new RedissonReadLocker(redissonClient));
    }

    public ServiceLocker getReentrantLocker() { return cacheLocker.get(Reentrant); }
    public ServiceLocker getFairLocker() { return cacheLocker.get(Fair); }
    public ServiceLocker getWriteLocker() { return cacheLocker.get(Write); }
    public ServiceLocker getReadLocker() { return cacheLocker.get(Read); }
}
```

**设计意图：** 单例模式 + 策略模式。所有 4 种锁实现创建一次，存放到 Map 中，后续通过 getter 获取。

#### ServiceLockFactory.java（锁工厂）

```java
@AllArgsConstructor
public class ServiceLockFactory {
    private final ManageLocker manageLocker;

    public ServiceLocker getLock(LockType lockType) {
        return switch (lockType) {
            case Fair -> manageLocker.getFairLocker();
            case Write -> manageLocker.getWriteLocker();
            case Read -> manageLocker.getReadLocker();
            default -> manageLocker.getReentrantLocker();  // 默认可重入锁
        };
    }
}
```

**这里为什么不直接注入 ManageLocker 而要再包一层 ServiceLockFactory？**

从职责分离的角度看，`ManageLocker` 只负责"管理锁实例的集合"，`ServiceLockFactory` 负责"根据 LockType 获取对应的锁"。调用方只需要 `serviceLockFactory.getLock(Reentrant)` 即可。

实际代码中 `ServiceLockAspect` 直接注入了 `ServiceLockFactory`，避免了与 `ManageLocker` 的直接耦合。

---

### 2.4 超时策略体系

#### LockTimeOutHandler.java（接口）

```java
@FunctionalInterface
public interface LockTimeOutHandler {
    void handler(String lockName);  // 获取锁超时后的处理逻辑
}
```

#### LockTimeOutStrategy.java（枚举实现）

```java
public enum LockTimeOutStrategy implements LockTimeOutHandler {
    FAIL() {
        @Override
        public void handler(String lockName) {
            String msg = String.format("%s请求频繁", lockName);
            throw new RuntimeException(msg);  // 默认：抛运行时异常
        }
    }
}
```

**设计模式分析：策略模式 + 枚举单例**

这里用 **枚举** 实现了策略模式，每个枚举常量是 `LockTimeOutHandler` 接口的一个实现。当前只有 `FAIL`（抛出"请求频繁"异常），后续可以扩展：
```java
TRY_AGAIN() {
    @Override
    public void handler(String lockName) {
        // 重试逻辑
    }
},
WAIT() {
    @Override
    public void handler(String lockName) {
        // 阻塞等待
    }
}
```

**@ServiceLock 中的 customLockTimeoutStrategy 属性**

除了枚举策略，还可以在注解中指定**自定义超时处理方法名**：

```java
@ServiceLock(name="pay", keys={"#orderId"},
             lockTimeoutStrategy = LockTimeOutStrategy.FAIL,
             customLockTimeoutStrategy = "onLockTimeout")
public String pay(String orderId) {
    // 正常业务
}

// 超时时的自定义回调：必须与目标方法参数列表一致
public String onLockTimeout(String orderId) {
    // 返回友好的降级响应
    return "当前人数过多，请稍后再试";
}
```

---

### 2.5 核心：@ServiceLock 注解与 AOP 切面

#### ServiceLock.java（注解定义）

```java
@Target({ElementType.TYPE, ElementType.METHOD})  // 可用在类或方法上
@Retention(RetentionPolicy.RUNTIME)                // 运行时保留（反射可读取）
public @interface ServiceLock {
    LockType lockType() default LockType.Reentrant;          // 锁类型
    String name() default "";                                 // 业务名称
    String[] keys();                                          // 锁 Key（支持 SpEL）
    long waitTime() default 10;                               // 等待超时（秒）
    TimeUnit timeUnit() default TimeUnit.SECONDS;
    LockTimeOutStrategy lockTimeoutStrategy() default LockTimeOutStrategy.FAIL;  // 超时策略
    String customLockTimeoutStrategy() default "";            // 自定义超时处理方法名
}
```

**注解属性详解：**

| 属性 | 默认值 | 说明 | 示例 |
|------|--------|------|------|
| `lockType` | `Reentrant` | 锁类型 | `Reentrant` / `Fair` / `Read` / `Write` |
| `name` | `""` | 业务名称，用于锁名 | `"createOrder"` |
| `keys` | 必填 | 锁标识，SpEL 表达式 | `{"#orderId", "#userId"}` |
| `waitTime` | `10` | 获取锁的最大等待时间 | `3`（秒） |
| `timeUnit` | `SECONDS` | 时间单位 | `TimeUnit.MILLISECONDS` |
| `lockTimeoutStrategy` | `FAIL` | 超时后的策略 | `LockTimeOutStrategy.FAIL` |
| `customLockTimeoutStrategy` | `""` | 自定义超时回调方法 | `"handleTimeout"` |

#### ServiceLockAspect.java（核心切面）

```java
@Slf4j
@Aspect
@Order(-10)          // 高优先级：让锁切面在其他切面之前执行
@AllArgsConstructor
public class ServiceLockAspect {

    private final LockInfoHandleFactory lockInfoHandleFactory;
    private final ServiceLockFactory serviceLockFactory;

    @Around("@annotation(servicelock)")
    public Object around(ProceedingJoinPoint joinPoint, ServiceLock servicelock) throws Throwable {
        // ── 第 1 步：构建锁名 ──
        // 从 Factory 中获取 "service_lock" 类型的 LockInfoHandle
        LockInfoHandle lockInfoHandle = lockInfoHandleFactory.getLockInfoHandle(LockInfoType.SERVICE_LOCK);
        // 通过 AbstractLockInfoHandle 解析 SpEL，生成完整锁名
        String lockName = lockInfoHandle.getLockName(joinPoint, servicelock.name(), servicelock.keys());
        // 结果示例: "damai-order-service-SERVICE_LOCK:create:ORD123"

        // ── 第 2 步：获取锁类型 ──
        LockType lockType = servicelock.lockType();
        long waitTime = servicelock.waitTime();
        TimeUnit timeUnit = servicelock.timeUnit();

        // ── 第 3 步：尝试加锁 ──
        ServiceLocker lock = serviceLockFactory.getLock(lockType);
        boolean result = lock.tryLock(lockName, timeUnit, waitTime);

        if (result) {
            // ── 第 4 步：加锁成功 → 执行业务逻辑 ──
            try {
                return joinPoint.proceed();
            } finally {
                // ── 第 5 步：解锁（保证一定执行） ──
                lock.unlock(lockName);
            }
        } else {
            // ── 第 6 步：加锁超时 → 执行超时策略 ──
            log.warn("Timeout while acquiring serviceLock:{}", lockName);
            String customLockTimeoutStrategy = servicelock.customLockTimeoutStrategy();
            if (StringUtil.isNotEmpty(customLockTimeoutStrategy)) {
                // 优先：调用自定义超时处理方法
                return handleCustomLockTimeoutStrategy(customLockTimeoutStrategy, joinPoint);
            } else {
                // 默认：使用枚举策略（抛异常）
                servicelock.lockTimeoutStrategy().handler(lockName);
            }
            return joinPoint.proceed();
        }
    }
```

**逐行拆解核心逻辑：**

| 行 | 代码 | 详解 |
|----|------|------|
| `@Around("@annotation(servicelock)")` | 切点表达式 | 匹配所有方法上标注了 `@ServiceLock` 的方法，并将注解内容绑定到参数 `servicelock` |
| `lockInfoHandleFactory.getLockInfoHandle(LockInfoType.SERVICE_LOCK)` | 工厂模式 | 从 Spring 容器中获取名为 `"service_lock"` 的 `LockInfoHandle` Bean |
| `lockInfoHandle.getLockName(joinPoint, name, keys)` | 锁名构建 | 进入 `AbstractLockInfoHandle`，SpEL 解析 keys 数组 |
| `serviceLockFactory.getLock(lockType)` | 策略模式 | 根据注解的 `lockType` 获取对应的 `ServiceLocker` 实现 |
| `lock.tryLock(lockName, timeUnit, waitTime)` | 非阻塞加锁 | Redisson 的 `tryLock` 如果 `waitTime` 内获取不到锁，返回 false。**不会阻塞超过 waitTime** |
| `joinPoint.proceed()` | 执行业务 | 如果获取到锁，执行目标方法 |
| `lock.unlock(lockName)` | 解锁 | 放在 `finally` 中，保证无论业务是否抛异常都**释放锁** |
| `handleCustomLockTimeoutStrategy(...)` | 自定义回调 | 通过反射调用目标类中指定的超时处理方法 |

**@Order(-10) 的意义：**

`@Order(-10)` 设置了该切面的优先级。数值越小优先级越高（越外层）。这里设为 -10 意味着锁切面**包裹**在业务切面之外，确保：
1. 先获取锁再执行业务
2. 业务完成后释放锁
3. 其他业务切面在锁的保护范围内执行

```java
    // 自定义超时策略的处理方法：通过反射调用
    public Object handleCustomLockTimeoutStrategy(String customLockTimeoutStrategy, JoinPoint joinPoint) {
        Method currentMethod = ((MethodSignature) joinPoint.getSignature()).getMethod();
        Object target = joinPoint.getTarget();              // 获取目标 Bean 实例
        Method handleMethod = null;
        try {
            // 从目标类中查找同名方法（参数列表必须一致）
            handleMethod = target.getClass().getDeclaredMethod(
                customLockTimeoutStrategy, currentMethod.getParameterTypes());
            handleMethod.setAccessible(true);               // 即使是 private 方法也能调用
        } catch (NoSuchMethodException e) {
            throw new RuntimeException("Illegal annotation param customLockTimeoutStrategy :" + customLockTimeoutStrategy, e);
        }
        Object[] args = joinPoint.getArgs();                // 获取原始方法的参数
        Object result;
        try {
            result = handleMethod.invoke(target, args);     // 反射调用超时处理方法
        } catch (IllegalAccessException | InvocationTargetException e) {
            throw new RuntimeException("Fail to invoke custom lock timeout handler", e);
        }
        return result;                                      // 返回降级结果
    }
}
```

**自定义超时处理完整示例：**

```java
@Service
public class OrderService {

    @ServiceLock(name="create", keys={"#createOrderReq.orderId"},
                 waitTime=3,
                 customLockTimeoutStrategy = "createOrderTimeout")
    public String createOrder(CreateOrderReq createOrderReq) {
        // 正常创建订单逻辑
        return "success";
    }

    // 超时回调方法：必须与目标方法参数列表一致
    public String createOrderTimeout(CreateOrderReq createOrderReq) {
        // 降级处理：返回友好的提示
        return "当前下单人数过多，请稍后重试";
    }
}
```

---

### 2.6 编程式锁：ServiceLockTool

除了注解声明式，框架还提供了 `ServiceLockTool` 用于**编程式加锁**场景。

#### TaskRun.java + TaskCall.java（函数式接口）

```java
@FunctionalInterface
public interface TaskRun {
    void run();          // 无返回值的任务
}

@FunctionalInterface
public interface TaskCall<V> {
    V call();            // 有返回值的任务
}
```

#### ServiceLockTool.java

```java
@AllArgsConstructor
public class ServiceLockTool {

    private final LockInfoHandleFactory lockInfoHandleFactory;
    private final ServiceLockFactory serviceLockFactory;

    // ── 无返回值（void） ──

    public void execute(TaskRun taskRun, String name, String[] keys) {
        execute(taskRun, name, keys, 20);                       // 默认等待 20 秒
    }

    public void execute(TaskRun taskRun, String name, String[] keys, long waitTime) {
        execute(LockType.Reentrant, taskRun, name, keys, waitTime);  // 默认可重入锁
    }

    public void execute(LockType lockType, TaskRun taskRun, String name, String[] keys, long waitTime) {
        // 1. 获取锁名（编程式用 simpleGetLockName，不解析 SpEL）
        LockInfoHandle lockInfoHandle = lockInfoHandleFactory.getLockInfoHandle(LockInfoType.SERVICE_LOCK);
        String lockName = lockInfoHandle.simpleGetLockName(name, keys);
        // 2. 根据类型获取锁
        ServiceLocker lock = serviceLockFactory.getLock(lockType);
        // 3. 尝试加锁
        boolean result = lock.tryLock(lockName, TimeUnit.SECONDS, waitTime);
        if (result) {
            try {
                taskRun.run();                                  // 执行业务
            } finally {
                lock.unlock(lockName);                          // 解锁
            }
        } else {
            LockTimeOutStrategy.FAIL.handler(lockName);         // 超时处理
        }
    }

    // ── 有返回值 ──

    public <T> T submit(TaskCall<T> taskCall, String name, String[] keys) {
        LockInfoHandle lockInfoHandle = lockInfoHandleFactory.getLockInfoHandle(LockInfoType.SERVICE_LOCK);
        String lockName = lockInfoHandle.simpleGetLockName(name, keys);
        ServiceLocker lock = serviceLockFactory.getLock(LockType.Reentrant);  // 默认可重入
        boolean result = lock.tryLock(lockName, TimeUnit.SECONDS, 30);
        if (result) {
            try {
                return taskCall.call();                         // 执行业务 + 返回结果
            } finally {
                lock.unlock(lockName);
            }
        } else {
            LockTimeOutStrategy.FAIL.handler(lockName);
        }
        return null;
    }

    // ── 获取锁对象（手动控制） ──

    public RLock getLock(LockType lockType, String name, String[] keys) {
        LockInfoHandle lockInfoHandle = lockInfoHandleFactory.getLockInfoHandle(LockInfoType.SERVICE_LOCK);
        String lockName = lockInfoHandle.simpleGetLockName(name, keys);
        ServiceLocker lock = serviceLockFactory.getLock(lockType);
        return lock.getLock(lockName);
    }

    public RLock getLock(LockType lockType, String lockName) {
        ServiceLocker lock = serviceLockFactory.getLock(lockType);
        return lock.getLock(lockName);
    }
}
```

**使用示例：**

```java
@Service
public class OrderService {

    @Autowired
    private ServiceLockTool serviceLockTool;

    // 无返回值
    public void cancelOrder(String orderId) {
        serviceLockTool.execute(() -> {
            // 加锁执行的取消订单逻辑
            doCancel(orderId);
        }, "cancelOrder", new String[]{orderId});
    }

    // 有返回值
    public String payOrder(String orderId) {
        return serviceLockTool.submit(() -> {
            return doPay(orderId);
        }, "payOrder", new String[]{orderId});
    }
}
```

**注解式 vs 编程式对比：**

| 维度 | 注解式 @ServiceLock | 编程式 ServiceLockTool |
|------|-------------------|----------------------|
| 使用方式 | 声明式，AOP 自动拦截 | 手动在代码中调用 |
| 侵入性 | 低（只需加注解） | 高（需要在方法内写代码） |
| 灵活性 | 固定加锁范围（整个方法） | 灵活（可控制方法内某段代码加锁） |
| 锁名前缀 | `SERVICE_LOCK` | `LOCK_DISTRIBUTE_ID` |
| 返回值处理 | 自动 | 通过 `submit()` 支持 |

---

### 2.7 Spring 自动装配

#### ServiceLockAutoConfiguration.java

```java
public class ServiceLockAutoConfiguration {

    // 注册 ServiceLockInfoHandle，Bean 名为 "service_lock"
    @Bean(LockInfoType.SERVICE_LOCK)
    public LockInfoHandle serviceLockInfoHandle() {
        return new ServiceLockInfoHandle();
    }

    @Bean
    public ManageLocker manageLocker(RedissonClient redissonClient) {
        return new ManageLocker(redissonClient);
    }

    @Bean
    public ServiceLockFactory serviceLockFactory(ManageLocker manageLocker) {
        return new ServiceLockFactory(manageLocker);
    }

    @Bean
    public ServiceLockAspect serviceLockAspect(
            LockInfoHandleFactory lockInfoHandleFactory,
            ServiceLockFactory serviceLockFactory) {
        return new ServiceLockAspect(lockInfoHandleFactory, serviceLockFactory);
    }

    @Bean
    public ServiceLockTool serviceLockUtil(
            LockInfoHandleFactory lockInfoHandleFactory,
            ServiceLockFactory serviceLockFactory) {
        return new ServiceLockTool(lockInfoHandleFactory, serviceLockFactory);
    }
}
```

**关键点：**

1. `@Bean(LockInfoType.SERVICE_LOCK)` — 将 `ServiceLockInfoHandle` 的 Bean 名称注册为 `"service_lock"`（即 `LockInfoType.SERVICE_LOCK` 常量的值）。这样 `LockInfoHandleFactory.getLockInfoHandle("service_lock")` 才能找到它。

2. 所有 Bean 的创建都依赖于之前在 `RedissonCommonAutoConfiguration` 中创建好的 `RedissonClient`、`LockInfoHandleFactory`。

3. 自动配置需要注册在 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`：
```
com.damai.config.ServiceLockAutoConfiguration
```

---

## 三、Redisson 底层原理（八股详解）

### 3.1 Redisson tryLock 原理

当调用 `redissonClient.getLock(key).tryLock(waitTime, leaseTime, unit)` 时，Redisson 做了什么：

```
1. 尝试用 Lua 脚本原子执行：SET key value EX seconds NX
2. 如果成功 → 获取到锁
3. 如果失败 → 订阅 Redis 的 channel（发布/订阅模式），等待其他线程释放锁
4. 等待 waitTime 时间，如果期间收到解锁消息，再次尝试获取
5. 超时仍没获取到 → 返回 false
```

**核心：** Redisson 的锁是基于 Redis 的发布/订阅 + Lua 脚本 + 信号量实现的，比自旋（while true）效率高得多。

### 3.2 WatchDog（看门狗）自动续期

```
线程A获取锁成功 (leaseTime=30秒)
    ↓
后台定时任务（每10秒执行一次）检查锁是否还在
    ↓
如果业务还没执行完 → 重新设置锁过期时间为30秒
    ↓
如果业务执行完了 → lock.unlock() 手动释放锁，停止续期
```

**为什么需要 WatchDog？**

因为 `tryLock` 有 leaseTime，如果业务执行时间超过了 leaseTime，锁会自动释放，其他线程就能获取到锁，导致并发问题。WatchDog 保证了**业务没执行完，锁不会自动释放**。

### 3.3 Lua 脚本保证原子性

Redisson 加锁的 Lua 脚本（简化版）：

```lua
-- 如果锁不存在
if (redis.call('exists', KEYS[1]) == 0) then
    -- 创建锁，hash结构，field是线程ID
    redis.call('hset', KEYS[1], ARGV[2], 1);
    -- 设置过期时间
    redis.call('pexpire', KEYS[1], ARGV[1]);
    return nil;
end;

-- 如果锁存在且是同一个线程（可重入）
if (redis.call('hexists', KEYS[1], ARGV[2]) == 1) then
    -- 重入计数 +1
    redis.call('hincrby', KEYS[1], ARGV[2], 1);
    redis.call('pexpire', KEYS[1], ARGV[1]);
    return nil;
end;

-- 锁被其他线程持有，返回剩余时间
return redis.call('pttl', KEYS[1]);
```

**为什么用 Lua？** 因为 Lua 脚本在 Redis 中**原子执行**，中间不会被其他命令插入，保证「检查-设置」的原子性。

### 3.4 四种锁的 Redis 数据结构

| 锁类型 | Redis 数据结构 | 公平性实现 |
|--------|---------------|-----------|
| 可重入锁 | Hash（field=线程ID, value=重入计数） | 无 |
| 公平锁 | Hash + List（排队队列） | Redis List 维护请求顺序 |
| 读写锁 | Hash + 两个 Key（读模式/写模式） | 模式互斥 |

---

## 四、方案对比

### 4.1 基于 Redis 的分布式锁方案对比

| 方案 | 实现原理 | 优点 | 缺点 |
|------|---------|------|------|
| **SETNX + Lua**（自研） | `SET key value NX EX seconds` + Lua 脚本续期 | 简单、无依赖 | 需要自行实现续期、可重入、公平锁 |
| **Redisson**（本项目） | Redisson RLock（Lua + Pub/Sub + WatchDog） | 开箱即用、自动续期、可重入、多类型 | 依赖 Redisson 库 |
| **ZooKeeper** | 临时顺序节点 + Watcher | 强一致性、无过期问题 | 性能低、ZK 集群维护成本高 |
| **数据库唯一键** | `insert into lock_table values(key)` 成功即获锁 | 实现简单 | 性能极低、无超时机制 |

### 4.2 为什么本项目选择 Redisson？

| 需求 | Redisson 回答 | 替代方案瓶颈 |
|------|--------------|-------------|
| 高并发（万级 TPS） | Redis 内存操作，单机 10w+ QPS | ZK 写性能只有几千 QPS |
| 自动续期 | WatchDog 后台线程 | SETNX 需要自己实现续期逻辑 |
| 多种锁类型 | Reentrant/Fair/Read/Write | SETNX 只能实现最简单的可重入 |
| 微服务友好 | 与 Spring Boot 深度集成 | ZK 配置复杂 |

---

## 五、涉及八股知识点

| 八股 | 对应代码 | 说明 |
|------|---------|------|
| **AOP 环绕通知** | `@Around("@annotation(servicelock)")` | 在目标方法前后执行加锁/解锁 |
| **SpEL 表达式** | `parser.parseExpression("#orderId").getValue(context)` | Spring 表达式语言，在注解中动态引用方法参数 |
| **策略模式** | `LockTimeOutStrategy` 枚举 | 定义一组算法（超时处理），在运行时选择 |
| **模板方法模式** | `AbstractLockInfoHandle.getLockName()` | 父类定义骨架，子类实现 `getLockPrefixName()` |
| **工厂模式** | `LockInfoHandleFactory` / `ServiceLockFactory` | 根据类型获取对应的实现 |
| **WatchDog 续期** | Redisson RLock 内部 | 后台线程定时续期，防止锁提前过期 |
| **Lua 原子性** | Redisson 加锁/解锁脚本 | 保证多条 Redis 命令原子执行 |
| **可重入锁** | `redissonClient.getLock(key)` | 同一线程可多次加锁，需对应解锁 |
| **读写锁** | `getReadWriteLock().readLock()` / `.writeLock()` | 读读不互斥，读写/写写互斥 |
| **公平锁** | `getFairLock(key)` | 基于 Redis List 实现 FIFO |
| **反射调用** | `handleMethod.invoke(target, args)` | 在 AOP 中动态调用自定义超时处理方法 |
| **finally 解锁** | `try { ... } finally { lock.unlock(); }` | 保证锁一定释放，防止死锁 |
| **@Order 切面优先级** | `@Order(-10)` | 控制多个 AOP 的执行顺序 |
| **ApplicationContextAware** | `LockInfoHandleFactory` | 在非 Spring 管理的 Bean 中获取容器引用 |
| **Spring 自动配置** | `AutoConfiguration.imports` | `spring.factories` 的替代，Spring Boot 2.7+ 推荐方式 |

---

## 六、使用示例

```java
@Service
public class ProgramService {

    // ── 场景1：防止重复创建（SpEL 引用对象属性） ──
    @ServiceLock(name="createProgram",
                 keys={"#req.programId", "#req.userId"},
                 lockType = LockType.Fair,
                 waitTime = 5,
                 lockTimeoutStrategy = LockTimeOutStrategy.FAIL)
    public Long createProgram(ProgramCreateReq req) {
        // 创建节目...
        return programId;
    }

    // ── 场景2：读操作使用读锁 ──
    @ServiceLock(name="queryProgram",
                 keys={"#programId"},
                 lockType = LockType.Read)
    public ProgramVo getProgram(Long programId) {
        return programService.getById(programId);
    }

    // ── 场景3：编程式精细加锁 ──
    @Autowired
    private ServiceLockTool lockTool;

    public void complexBusiness(Long orderId, Long userId) {
        // 只有这段代码需要加锁，不是整个方法
        lockTool.execute(() -> {
            doCoreBusiness(orderId, userId);
        }, "coreBiz", new String[]{String.valueOf(orderId)});
    }
}
```
