# curl Secure Transport 恢复补丁

## 背景

curl 从 8.15.0 起移除了 Secure Transport (sectransp) TLS 后端（commit `08a3e8e19a`）。
EMASCurl 的 HTTP/2 subspec 依赖 Secure Transport 以保持较小的二进制体积（~0.4MB vs OpenSSL ~3.3MB），
同时需要升级到 8.17.0 以对齐 iOS 系统库的 Happy Eyeballs v2 并发连接策略。

本补丁在 curl 8.17.0 (`curl-8_17_0` tag) 基础上恢复了 Secure Transport 后端支持。

## 补丁内容

- `0001-Secure-Transport-TLS-8.15.0.patch`
  - 基于 tag: `curl-8_17_0`
  - 恢复 sectransp.c / sectransp.h 及相关条件编译
  - 适配 8.15.0→8.17.0 期间的框架接口变更（send/recv 签名、ALPN 上报方式等）
  - 恢复 cipher_suite.c、x509asn1.c/h、curl_ntlm_core.c 中被删除的 Secure Transport 代码路径

## 使用方法

```bash
# 在 curl/ 子目录下，基于 curl-8_17_0 应用补丁
cd curl
git checkout curl-8_17_0
git am ../patches/0001-Secure-Transport-TLS-8.15.0.patch

# 然后执行构建
cd ..
./build_libcurl_http2.sh
```

## 升级 curl 版本

如需升级到更新的 curl 版本（如 8.18.0）：

```bash
cd curl
git checkout curl-8_18_0
git am ../patches/0001-Secure-Transport-TLS-8.15.0.patch
# 如有冲突，手动解决后：
# git am --continue
# 解决完毕后重新导出 patch：
# git format-patch curl-8_18_0..HEAD -o ../patches/
```

