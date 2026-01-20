local multipart = require("mote.parser.multipart")

describe("multipart", function()
    it("detects multipart content type and extracts boundary", function()
        assert.is_true(multipart.is_multipart("multipart/form-data; boundary=----WebKitFormBoundary"))
        assert.is_falsy(multipart.is_multipart("application/json"))
        assert.is_falsy(multipart.is_multipart(nil))

        local boundary = multipart.get_boundary("multipart/form-data; boundary=----WebKitFormBoundary")
        assert.are.equal("----WebKitFormBoundary", boundary)
    end)

    it("parses simple form field", function()
        local boundary = "----TestBoundary"
        local body = "------TestBoundary\r\n"
            .. 'Content-Disposition: form-data; name="title"\r\n'
            .. "\r\n"
            .. "Hello World\r\n"
            .. "------TestBoundary--\r\n"

        local parts = multipart.parse(body, boundary)
        assert.is_truthy(parts)
        assert.is_truthy(parts.title)
        assert.are.equal("Hello World", parts.title.data)
    end)

    it("parses file upload", function()
        local boundary = "----TestBoundary"
        local body = "------TestBoundary\r\n"
            .. 'Content-Disposition: form-data; name="document"; filename="test.txt"\r\n'
            .. "Content-Type: text/plain\r\n"
            .. "\r\n"
            .. "file content here\r\n"
            .. "------TestBoundary--\r\n"

        local parts = multipart.parse(body, boundary)
        assert.is_truthy(parts)
        assert.is_truthy(parts.document)
        assert.are.equal("test.txt", parts.document.filename)
        assert.are.equal("text/plain", parts.document.content_type)
        assert.are.equal("file content here", parts.document.data)
        assert.is_true(multipart.is_file(parts.document))
    end)

    it("parses mixed fields and files", function()
        local boundary = "----TestBoundary"
        local body = "------TestBoundary\r\n"
            .. 'Content-Disposition: form-data; name="title"\r\n'
            .. "\r\n"
            .. "My Document\r\n"
            .. "------TestBoundary\r\n"
            .. 'Content-Disposition: form-data; name="file"; filename="doc.pdf"\r\n'
            .. "Content-Type: application/pdf\r\n"
            .. "\r\n"
            .. "PDF CONTENT\r\n"
            .. "------TestBoundary--\r\n"

        local parts = multipart.parse(body, boundary)
        assert.is_truthy(parts.title)
        assert.is_truthy(parts.file)
        assert.are.equal("My Document", parts.title.data)
        assert.are.equal("doc.pdf", parts.file.filename)
        assert.is_falsy(multipart.is_file(parts.title))
        assert.is_true(multipart.is_file(parts.file))
    end)

    it("identifies file parts", function()
        local file_part = { name = "doc", filename = "test.pdf", data = "content" }
        local field_part = { name = "title", data = "Hello" }

        assert.is_true(multipart.is_file(file_part))
        assert.is_falsy(multipart.is_file(field_part))
        assert.is_falsy(multipart.is_file(nil))
    end)
end)
