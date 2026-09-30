# bigSeller · 大麦网项目拆解学习库

> 上游项目：[gitee.com/java-up-up/damai](https://gitee.com/java-up-up/damai)（大麦网票务系统，微服务架构）
> 本库是我学习拆解的全部产出 + 拆小后的学习版源码，已写入简历，长期维护。

## 结构

| 目录 | 内容 |
|---|---|
| `forStudy/` | 拆小后的学习版源码（含本机改动），学习实验直接在这里改 |
| `docs/` | 22 篇模块拆解笔记（Captcha/ES/ID生成/Redis/Redisson/线程池/各 Client 与 Service…）+ 依赖图 JSON |
| `bench/` | 压测脚本（bench-detail.mjs 等）+ `压测结果.md` + `docker-compose.yml` |
| `scripts/` | 本地一键启停脚本（start-all-services.ps1 等 4 个） |
| `learn/` | Spring Boot 练手骨架 |
| `patches/` | `local-tweaks.patch`：让上游在本机跑起来的 5 处改动（+20/-6 行），基于 `base-commit.txt` |

## 上游完整克隆

`upstream/` 只在本地（git 历史 + 构建参考），不入库。重新获取：

```powershell
git clone https://gitee.com/java-up-up/damai.git upstream
cd upstream
git apply ..\patches\local-tweaks.patch
```

## 学习路线（按依赖顺序）

1. `docs/damai-common.md` → 公共层
2. Redis Tool / Redisson / Thread Pool Framework → 三大基础框架
3. User/Order/Pay/Program Client → 业务接口层
4. Admin Service / Base Data Service → 业务实现层
