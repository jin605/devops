<%@ page import="java.net.InetAddress" %>
<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<% InetAddress inet = InetAddress.getLocalHost(); %>
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>Test Web</title>
</head>
<body>
    <h1>TEST WEB v3</h1>

    Server IP Address : <%=inet.getHostAddress()%>
</body>
</html>