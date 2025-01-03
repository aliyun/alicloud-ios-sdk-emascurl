# 测试说明
EMASCurl是基于libcurl封装实现的应用层网络库，重在提供一套方便的接口可以桥接到NSURLSession，同时提供方便的接入HTTPDNS的方法，使得业务可以尽量无感接入。

在设计测试用例时，我们的关注点不是网络请求本身的正确性或者性能，因为这由libcurl来保障。EMASCurl的测试用例更应该关注桥接之后的NSURLSession的功能正确性，比如超时设置、中途取消、进度回调等。

# 测试前提
为了测试用例不依赖外部服务稳定性或者网络稳定性，测试中我们需要起一个MockServer提供测试用的HTTP服务。相关文件放在`../MockServer`路径下。

运行以下命令，会同时启动一个监听在9080端口的HTTP1.1服务和一个监听在9443端口的HTTP2服务：

```python
python3 server.py
```

# 测试用例
测试用例包含以下这些场景
- 基本的GET、PUT、POST、DELETE、OPTION、HEAD请求
- 重定向
- 数据下载场景和中途取消
- 数据上传场景和中途取消
