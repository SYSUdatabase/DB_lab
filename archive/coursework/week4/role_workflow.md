# v0.1 角色—数据库操作流程图

> 场景：API Token 中转站　数据库：`TokenHubDB_v01_*`
> 配套脚本：`sql/role.sql`、`sql/view.sql`、`sql/query.sql`、`sql/constraint.sql`
> 本图与 `sql/role.sql` 的实际授权一一对应；会员写操作推迟到第三阶段存储过程，原因见文末。

## 0. 角色与数据库身份

| 业务角色 | SQL Server 角色 | 演示用户（WITHOUT LOGIN） | 职责范围 |
|---|---|---|---|
| 游客 | `hub_guest` | `hub_guest_demo` | 只读在售商品目录 |
| 会员 | `hub_customer` | `hub_user_1`、`hub_user_2` | 本人订单、余额、用量 |
| 店员（客服/运营） | `hub_staff` | `hub_staff_demo` | 经营视图、订单状态处理、客服信息查询 |
| 店长（管理员） | `hub_manager` | `hub_manager_demo` | 14 张业务表 CRUD、员工角色、经营分析 |

> `dbo.Roles` 是应用层角色描述数据，`hub_guest/hub_customer/hub_staff/hub_manager` 才是 SQL Server DATABASE ROLE，两者分开设计。

## 1. 总图：四个角色到数据库的完整链路

```mermaid
flowchart TD
  subgraph G["游客 hub_guest"]
    G1["浏览在售商品"] --> G2["SELECT v_ProductCatalog"] --> G3["无账号不能下单"]
  end

  subgraph C["会员 hub_customer"]
    C1["SELECT v_ProductCatalog"] --> C2["SELECT v_MyOrders v_MyBalances v_MyUsage"]
    C2 --> C3["USER_NAME 映射到本人 user_id"]
    C3 -.->|第三阶段| C4["存储过程下单 支付 改资料"]
  end

  subgraph S["店员 hub_staff"]
    S1["SELECT v_OrderDetail v_ProductSales v_MemberSpending"] --> S2["SELECT v_InventoryStatus 判断 stock_state=low"]
    S2 --> S3["UPDATE v_StaffOrderQueue.status"]
    S3 --> S4["SELECT v_CustomerService 联系客户 不含 password_hash"]
  end

  subgraph A["店长 hub_manager"]
    A1["CRUD 14 张业务表"] --> A2["维护 Employees Roles 授权"] --> A3["读取全部 10 个视图 做经营分析"]
  end

  DB["数据库 TokenHubDB_v01_x<br/>14 张业务表 + 10 个视图"]

  subgraph GATE["权限与约束闸门"]
    P1{"角色是否有权限"}
    P2{"是否写入"}
    P3{"约束是否通过"}
    P4["COMMIT 提交"]
    P5["拒绝并 ROLLBACK"]
    P1 -->|允许| P2
    P1 -->|拒绝| P5
    P2 -->|只读| P4
    P2 -->|写入| P3
    P3 -->|通过| P4
    P3 -->|不通过| P5
  end

  G2 --> DB
  C2 --> DB
  S4 --> DB
  A1 --> DB
  DB --> P1

  classDef deny fill:#ffe5e5,stroke:#c62828
  classDef ok fill:#e7f4e8,stroke:#2e7d32
  classDef later fill:#fff8e1,stroke:#f9a825
  class G3,C4,P5 deny
  class C4 later
  class P4 ok
```

## 2. 子流程一：游客（`hub_guest`）

```mermaid
flowchart TD
  A["访问店铺页面"] --> B["SELECT v_ProductCatalog<br/>只返回 status=active 商品"]
  B --> C["查看单价 Token 面额 provider"]
  C --> D{"是否要下单"}
  D -->|否| E["离开 只有读操作"]
  D -->|是| F{"是否已注册"}
  F -->|否| G["提示注册 流程终止"]
  F -->|是| H["转入会员流程"]

  X["反例 游客 SELECT v_MyOrders"] --> X1["无授权 错误 229"]
  X1 --> X2["返回零行 数据不泄露"]

  classDef deny fill:#ffe5e5,stroke:#c62828
  classDef ok fill:#e7f4e8,stroke:#2e7d32
  class G,X1,X2 deny
  class E ok
```

## 3. 子流程二：会员（`hub_customer`）

```mermaid
flowchart TD
  A["登录 应用校验 Users.status"] --> B["SELECT v_ProductCatalog"]
  B --> C["SELECT v_MyOrders v_MyBalances v_MyUsage<br/>视图内用 USER_NAME 锁定本人 user_id"]
  C --> D{"是否下单"}
  D -->|否| E["查看本人数据 结束"]
  D -->|是| F["第三阶段 调用 sp_PlaceOrder<br/>过程内校验 USER_NAME 与 user_id 一致"]
  F --> G["sp_PayOrder 写 paid 与 paid_at"]
  G --> H["过程内事务写 TokenBalances 与流水"]

  X1["反例 会员 SELECT dbo.Orders"] --> X2["未授权基表 错误 229"]
  X3["反例 会员查他人订单"] --> X4["v_MyOrders 内 user_id 不匹配 返回空集"]
  X5["反例 会员 SELECT v_CustomerService"] --> X6["客服视图未授权 错误 229"]
  X7["反例 会员 INSERT dbo.Orders"] --> X8["无 INSERT 权限 错误 229"]

  classDef deny fill:#ffe5e5,stroke:#c62828
  classDef ok fill:#e7f4e8,stroke:#2e7d32
  classDef later fill:#fff8e1,stroke:#f9a825
  class X2,X4,X6,X8 deny
  class F,G,H later
  class E ok
```

## 4. 子流程三：店员（`hub_staff`）

```mermaid
flowchart TD
  A["EXECUTE AS hub_staff_demo"] --> B["SELECT v_OrderDetail v_ProductSales v_MemberSpending"]
  B --> C{"队列里有 pending 订单"}
  C -->|是| D["UPDATE v_StaffOrderQueue SET status<br/>仅 status 列被授权"]
  C -->|否| E["SELECT v_InventoryStatus"]
  D --> E
  E --> F{"stock_state = low"}
  F -->|否| G["无需补货 记录 quota_headroom"]
  F -->|是| H["SELECT v_CustomerService<br/>取联系方式 不含 password_hash"]
  H --> I["上报店长 由店长执行补货"]

  X1["反例 店员 UPDATE dbo.Products"] --> X2["未授权 错误 229"]
  X3["反例 店员 UPDATE v_StaffOrderQueue SET user_id"] --> X4["仅授权 status 列 错误 230"]
  X5["反例 店员 SELECT password_hash FROM dbo.Users"] --> X6["未授权基表 错误 229"]

  classDef deny fill:#ffe5e5,stroke:#c62828
  classDef ok fill:#e7f4e8,stroke:#2e7d32
  class X2,X4,X6 deny
  class D,G ok
```

## 5. 子流程四：店长（`hub_manager`）

```mermaid
flowchart TD
  A["EXECUTE AS hub_manager_demo"] --> B["INSERT UPDATE DELETE dbo.Products"]
  B --> C["校验 price 大于 0 name 与 provider+token_amount 唯一"]
  C --> D{"校验是否通过"}
  D -->|否| D1["拒绝非法商品数据"]
  D -->|是| E["商品上架成功"]
  E --> F["INSERT UPDATE dbo.UpstreamAccount dbo.Inventory"]
  F --> F1["INSERT dbo.InventoryLog purchase 或 restock"]
  F1 --> G["UPDATE dbo.RestockTask 审批与完成"]
  G --> H["维护 dbo.Employees dbo.Roles"]
  H --> I["SELECT 全部 10 个视图 做经营分析"]
  I --> J["CREATE ROLE GRANT REVOKE 授权"]
  J --> K["SELECT dbo.ExceptionLog 审计留痕"]

  X1["反例 删除有订单明细的商品"] --> X2["外键 FK_OrderDetails_Products 阻止删除"]
  X3["反例 把 price 改成 0"] --> X4["CHECK CK_Products_price 拒绝更新"]
  X5["反例 新增重名商品"] --> X6["UNIQUE UQ_Products_name 插入失败"]
  X7["反例 重复 provider+token_amount"] --> X8["UNIQUE UQ_Products_provider_tokens 错误 2627"]

  classDef deny fill:#ffe5e5,stroke:#c62828
  classDef ok fill:#e7f4e8,stroke:#2e7d32
  class D1,X2,X4,X6,X8 deny
  class K ok
```

## 6. 角色—权限矩阵

| 对象与操作 | 游客 `hub_guest` | 会员 `hub_customer` | 店员 `hub_staff` | 店长 `hub_manager` |
|---|:---:|:---:|:---:|:---:|
| `v_ProductCatalog` 读 | 读 | 读 | 读 | 读 |
| `v_OrderDetail` / `v_ProductSales` / `v_MemberSpending` 读 | — | — | 读 | 读 |
| `v_InventoryStatus` 读 | — | — | 读 | 读 |
| `v_CustomerService` 读（联系方式，无密码哈希） | — | — | 读 | 读 |
| `v_StaffOrderQueue` 读 | — | — | 读 | 读 |
| `v_StaffOrderQueue.status` 更新 | — | — | 仅此列 | 允许 |
| `v_MyOrders` / `v_MyBalances` / `v_MyUsage` 读 | — | 仅本人 | — | —（改读基表） |
| 14 张基表 SELECT | — | — | — | 允许 |
| 14 张基表 INSERT / UPDATE / DELETE | — | — | — | 允许 |
| 下单 / 支付 / 改本人资料 | — | 第三阶段存储过程 | — | 允许 |
| 补货 `RestockTask` / 库存写入 | — | — | 仅上报 | 允许 |
| `Users.password_hash` 读取 | — | — | — | 允许（基表 CRUD） |
| DDL / CONTROL / db_owner / sysadmin | — | — | — | — |

`verify.sql` VFY03 会自动复核该矩阵：会员与游客不得拥有任何写权限，会员与店员不得拥有任何基表权限，店长对 14 张表的 CRUD 授权必须齐全。

## 7. `role.sql` 执行顺序

1. `CREATE ROLE hub_manager / hub_staff / hub_customer / hub_guest`（已存在则跳过，可重复执行）；
2. `CREATE USER hub_*_demo / hub_user_1 / hub_user_2 ... WITHOUT LOGIN`，用于课程内 `EXECUTE AS` 演示，不写真实登录；
3. `ALTER ROLE ... ADD MEMBER` 只把演示用户加入对应角色，不建立任何固定高权限成员关系；
4. 按最小权限逐对象 `GRANT SELECT`，只对队列视图的 `status` 列 `GRANT UPDATE`，不使用 `GRANT ALL`；
5. 用表驱动用例 R01～R17 逐条执行正反例：正例必须执行成功，非法例必须匹配指定错误号（229/230）；
6. 追加 `sys.fn_my_permissions` 审计输出，列出店员在视图与基表上的实际权限，并校验店长管理权限；
7. 断言会员与店员在基表上没有权限、店长 CRUD 覆盖 14 张表、public 没有业务对象授权。

会员写权限为什么不在本阶段实现：见阶段报告的当前局限及本文件权限矩阵。直接授予 `INSERT ON Orders` 会让会员绕过“订单汇总 = 明细之和”“支付时间一致性”和 `USER_NAME()` 与目标 `user_id` 的比对；因此 v0.1 交付会员只读能力，下单、支付、修改本人资料统一由第三阶段存储过程在同一事务内完成并校验调用者身份。