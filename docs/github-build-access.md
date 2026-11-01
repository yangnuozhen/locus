# 为后续 GitHub Actions 构建提供访问权限

当前只修改源码，不推送、不触发 IPA 构建。准备好后提供可写仓库地址，并明确要求继续构建。

## 推荐：限定仓库的 Fine-grained personal access token

1. 打开 GitHub → 头像 → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**。
2. 选择拥有目标仓库权限的 Resource owner；Repository access 只选目标仓库，设置短期有效期。
3. Repository permissions 设置：
   - **Contents: Read and write**：推送修改后的源码。
   - **Workflows: Read and write**：提交新增或修改的 `.github/workflows` 文件。
   - **Actions: Read and write**：触发 workflow、读取构建状态及下载产物。
   - Metadata 的必需读取权限保持默认。无需管理员、删除仓库或组织管理权限。
4. 若仓库属于组织，确认组织允许该令牌，且所需审批已完成。令牌不能超越你本身的仓库权限。
5. 通过当前任务执行环境提供的 **Secrets / 安全环境变量**入口，将令牌配置为 **`GH_TOKEN`**。
   然后在聊天中仅提供仓库地址并告知授权已配置；不要粘贴令牌到聊天、源码、命令参数或日志中。

必须让凭据进入本任务可用的执行环境。仅在你自己电脑上运行 `gh auth login`，或仅把令牌
保存到目标仓库的 Actions secrets，不会让本任务获得推送和触发 workflow 的权限。
构建 workflow 自身使用 GitHub 自动提供的只读 `GITHUB_TOKEN`，无需将个人令牌转交给 runner。

我会用 GitHub CLI 验证账号与目标仓库权限，不输出凭据内容。构建完成后可撤销令牌。
如果当前平台没有向任务注入 Secrets 的入口，不要改用聊天发送令牌：可以由你自行提交源码，
在 GitHub 的 **Actions → Build unsigned IPA (artifact) → Run workflow** 运行并下载产物。

## 构建产物

新增 workflow 位于 `.github/workflows/unsigned-ipa.yml`，需要进入仓库的默认分支后才能从
Actions 手动触发。构建成功后下载名为 `Locus-unsigned-<commit>` 的 artifact，内含 IPA、
SHA-256 校验和、源码版本/状态及构建日志。产物保留 14 天，不发布 Release。

如果主分支有保护规则，先通过分支和 PR 合入构建入口，再触发对应源码版本；不需要关闭保护。
未签名 IPA 后续运行仍需签名或使用兼容容器。
