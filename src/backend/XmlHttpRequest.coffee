# A simple filesystem backed by XmlHttpRequests.
class BrowserFS.FileSystem.XmlHttpRequest extends BrowserFS.FileSystem
  # Constructs the file system.
  # @param [String] listing_path The path to the JSON file index generated by
  #   tools/XHRIndexer.coffee. This can be relative to the current webpage URL
  #   or absolutely specified.
  constructor: (listing_path='index.json') ->
    listing = @_request_file(listing_path, 'json')
    @index = BrowserFS.FileIndex.from_listing listing

  _request_file: (path, data_type, cb) ->
    # Ensure the file is in the index.
    return null if @index?.getInode(path) == null
    req = new XMLHttpRequest()
    req.open 'GET', path, cb?
    req.responseType = data_type
    data = null
    req.onerror = (e) -> console.error req.statusText
    req.onload = (e) ->
      unless req.readyState is 4 and req.status is 200
        console.error req.statusText
      return cb(req.response) if cb?
      data = req.response
    req.send()
    return data

  # Returns the name of the file system.
  # @return [String]
  getName: -> 'XmlHttpRequest'
  # Does the browser support XmlHttpRequest?
  # @return [Boolean]
  isAvailable: ->
    # Note: Older browsers use a different name for XHR, iirc.
    XMLHttpRequest?
  # Passes the size and taken space in bytes to the callback. Size will always
  # be equal to taken space, since this is a read-only file system.
  # @param [String] path Unused in the implementation.
  # @param [Function(Number, Number)] cb
  diskSpace: (path, cb) ->
    cb 0, 0
  # Returns true; this filesystem is read-only.
  # @return [Boolean]
  isReadOnly: -> true
  # Returns false; this filesystem does not support symlinks.
  # @return [Boolean]
  supportsLinks: -> false
  # Returns false; this filesystem does not support properties.
  # @return [Boolean]
  supportsProps: -> false

  # File or directory operations

  stat: (path, isLstat, cb) ->
    inode = @_index.getInode path
    if inode is null
      return cb new BrowserFS.ApiError BrowserFS.ApiError.NOT_FOUND, "#{path} not found."
    cb null, inode.getStats()

  # File operations

  open: (path, flags, mode, cb) ->
    # Check if the path exists, and is a file.
    inode = @_index.getInode path
    if inode isnt null
      unless inode.isFile()
        return cb new BrowserFS.ApiError BrowserFS.ApiError.NOT_FOUND, "#{path} is a directory."
      else
        switch flags.pathExistsAction()
          when BrowserFS.FileMode.THROW_EXCEPTION, BrowserFS.FileMode.TRUNCATE_FILE
            return cb new BrowserFS.ApiError BrowserFS.ApiError.INVALID_PARAM, "#{path} already exists."
          when BrowserFS.FileMode.NOP
            # Use existing file contents.
            @_request_file path, 'arraybuffer', (buffer) =>
              file = new BrowserFS.File.NoSyncFile @, path, flags, inode, buffer
              return cb null, file
          else
            return cb new BrowserFS.ApiError BrowserFS.ApiError.INVALID_PARAM, 'Invalid FileMode object.'
    else
      switch flags.pathNotExistsAction()
        when BrowserFS.FileMode.THROW_EXCEPTION, BrowserFS.FileMode.CREATE_FILE
          return cb new BrowserFS.ApiError BrowserFS.ApiError.INVALID_PARAM, "#{path} doesn't exist."
        else
          return cb new BrowserFS.ApiError BrowserFS.ApiError.INVALID_PARAM, 'Invalid FileMode object.'

  # Directory operations

  readdir: (path, cb) ->
    # Check if it exists.
    inode = @_index.getInode path
    if inode is null
      return cb new BrowserFS.ApiError BrowserFS.ApiError.NOT_FOUND, "#{path} not found."
    else if inode.isFile()
      return cb new BrowserFS.ApiError BrowserFS.ApiError.NOT_FOUND, "#{path} is a file, not a directory."
    cb null, inode.getListing()
