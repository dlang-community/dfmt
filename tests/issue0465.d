bool asdf(const string owner, const string mail) @safe
{
    requestHTTP(url, (scope HTTPClientRequest request) {
        request.writeFormBody([owner: owner, mail:
                mail]);
    }, (scope HTTPClientResponse response) {});

    return true;
}
