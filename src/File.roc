interface File
    exposes [ReadErr, WriteErr, write, writeUtf8, writeBytes, readUtf8, readBytes, delete, writeErrToStr, readErrToStr]
    imports [Task.{ Task }, InternalTask, InternalFile, Path.{ Path }, InternalPath, Effect.{ Effect }]

## Tag union of possible errors when reading a file or directory.
ReadErr : InternalFile.ReadErr

## Tag union of possible errors when writing a file or directory.
WriteErr : InternalFile.WriteErr

## Write data to a file. 
##
## First encode a `val` using a given `fmt` which implements the ability [Encode.EncoderFormatting](https://www.roc-lang.org/builtins/Encode#EncoderFormatting).
##
## For example, suppose you have a `Json.toCompactUtf8` which implements
## [Encode.EncoderFormatting](https://www.roc-lang.org/builtins/Encode#EncoderFormatting).
## You can use this to write [JSON](https://en.wikipedia.org/wiki/JSON)
## data to a file like this:
##
## ```
## # Writes `{"some":"json stuff"}` to the file `output.json`:
## File.write
##     (Path.fromStr "output.json")
##     { some: "json stuff" }
##     Json.toCompactUtf8
## ```
##
## This opens the file first and closes it after writing to it.
## If writing to the file fails, for example because of a file permissions issue, the task fails with [WriteErr].
##
## > To write unformatted bytes to a file, you can use [File.writeBytes] instead.
write : Path, val, fmt -> Task {} [FileWriteErr Path WriteErr] | val has Encode.Encoding, fmt has Encode.EncoderFormatting
write = \path, val, fmt ->
    bytes = Encode.toBytes val fmt

    # TODO handle encoding errors here, once they exist
    writeBytes path bytes

## Writes bytes to a file.
##
## ```
## # Writes the bytes 1, 2, 3 to the file `myfile.dat`.
## File.writeBytes (Path.fromStr "myfile.dat") [1, 2, 3]
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To format data before writing it to a file, you can use [File.write] instead.
writeBytes : Path, List U8 -> Task {} [FileWriteErr Path WriteErr]
writeBytes = \path, bytes ->
    toWriteTask path \pathBytes -> Effect.fileWriteBytes pathBytes bytes

## Writes a [Str] to a file, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Writes "Hello!" encoded as UTF-8 to the file `myfile.txt`.
## File.writeUtf8 (Path.fromStr "myfile.txt") "Hello!"
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To write unformatted bytes to a file, you can use [File.writeBytes] instead.
writeUtf8 : Path, Str -> Task {} [FileWriteErr Path WriteErr]
writeUtf8 = \path, str ->
    toWriteTask path \bytes -> Effect.fileWriteUtf8 bytes str

## Deletes a file from the filesystem. 
##
## Performs a [`DeleteFile`](https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-deletefile)
## on Windows and [`unlink`](https://en.wikipedia.org/wiki/Unlink_(Unix)) on
## UNIX systems. On Windows, this will fail when attempting to delete a readonly
## file; the file's readonly permission must be disabled before it can be
## successfully deleted.
##
## ```
## # Deletes the file named
## File.delete (Path.fromStr "myfile.dat") [1, 2, 3]
## ```
##
## > This does not securely erase the file's contents from disk; instead, the operating
## system marks the space it was occupying as safe to write over in the future. Also, the operating
## system may not immediately mark the space as free; for example, on Windows it will wait until
## the last file handle to it is closed, and on UNIX, it will not remove it until the last
## [hard link](https://en.wikipedia.org/wiki/Hard_link) to it has been deleted.
##
delete : Path -> Task {} [FileWriteErr Path WriteErr]
delete = \path ->
    toWriteTask path \bytes -> Effect.fileDelete bytes

## Reads all the bytes in a file.
##
## ```
## # Read all the bytes in `myfile.txt`.
## File.readBytes (Path.fromStr "myfile.txt")
## ```
##
## This opens the file first and closes it after reading its contents.
##
## > To read and decode data from a file, you can use `File.read` instead.
readBytes : Path -> Task (List U8) [FileReadErr Path ReadErr]
readBytes = \path ->
    toReadTask path \bytes -> Effect.fileReadBytes bytes

## Reads a [Str] from a file containing [UTF-8](https://en.wikipedia.org/wiki/UTF-8)-encoded text.
##
## ```
## # Reads UTF-8 encoded text into a Str from the file "myfile.txt"
## File.readUtf8 (Path.fromStr "myfile.txt")
## ```
##
## This opens the file first and closes it after writing to it.
## The task will fail with `FileReadUtf8Err` if the given file contains invalid UTF-8.
##
## > To read unformatted bytes from a file, you can use [File.readBytes] instead.
readUtf8 : Path -> Task Str [FileReadErr Path ReadErr, FileReadUtf8Err Path _]
readUtf8 = \path ->
    effect = Effect.map (Effect.fileReadBytes (InternalPath.toBytes path)) \result ->
        when result is
            Ok bytes ->
                Str.fromUtf8 bytes
                |> Result.mapErr \err -> FileReadUtf8Err path err

            Err readErr -> Err (FileReadErr path readErr)

    InternalTask.fromEffect effect

# read :
#     Path,
#     fmt
#     -> Task
#         Str
#         [FileReadErr Path ReadErr, FileReadDecodeErr Path [Leftover (List U8)]Decode.DecodeError ]
#         [Read [File]]
#     | val has Decode.Decoding, fmt has Decode.DecoderFormatting
# read = \path, fmt ->
#     effect = Effect.map (Effect.fileReadBytes (InternalPath.toBytes path)) \result ->
#         when result is
#             Ok bytes ->
#                 when Decode.fromBytes bytes fmt is
#                     Ok val -> Ok val
#                     Err decodingErr -> Err (FileReadDecodeErr decodingErr)
#             Err readErr -> Err (FileReadErr readErr)
#     InternalTask.fromEffect effect
toWriteTask : Path, (List U8 -> Effect (Result ok err)) -> Task ok [FileWriteErr Path err]
toWriteTask = \path, toEffect ->
    InternalPath.toBytes path
    |> toEffect
    |> InternalTask.fromEffect
    |> Task.mapErr \err -> FileWriteErr path err

toReadTask : Path, (List U8 -> Effect (Result ok err)) -> Task ok [FileReadErr Path err]
toReadTask = \path, toEffect ->
    InternalPath.toBytes path
    |> toEffect
    |> InternalTask.fromEffect
    |> Task.mapErr \err -> FileReadErr path err

## Converts a [WriteErr] to a [Str].
writeErrToStr : WriteErr -> Str
writeErrToStr = \err ->
    when err is
        NotFound -> "NotFound"
        Interrupted -> "Interrupted"
        InvalidFilename -> "InvalidFilename"
        PermissionDenied -> "PermissionDenied"
        TooManySymlinks -> "TooManySymlinks"
        TooManyHardlinks -> "TooManyHardlinks"
        TimedOut -> "TimedOut"
        StaleNetworkFileHandle -> "StaleNetworkFileHandle"
        ReadOnlyFilesystem -> "ReadOnlyFilesystem"
        AlreadyExists -> "AlreadyExists"
        WasADirectory -> "WasADirectory"
        WriteZero -> "WriteZero"
        StorageFull -> "StorageFull"
        FilesystemQuotaExceeded -> "FilesystemQuotaExceeded"
        FileTooLarge -> "FileTooLarge"
        ResourceBusy -> "ResourceBusy"
        ExecutableFileBusy -> "ExecutableFileBusy"
        OutOfMemory -> "OutOfMemory"
        Unsupported -> "Unsupported"
        _ -> "Unrecognized"

## Converts a [ReadErr] to a [Str].
readErrToStr : ReadErr -> Str
readErrToStr = \err ->
    when err is
        NotFound -> "NotFound"
        Interrupted -> "Interrupted"
        InvalidFilename -> "InvalidFilename"
        PermissionDenied -> "PermissionDenied"
        TooManySymlinks -> "TooManySymlinks"
        TooManyHardlinks -> "TooManyHardlinks"
        TimedOut -> "TimedOut"
        StaleNetworkFileHandle -> "StaleNetworkFileHandle"
        OutOfMemory -> "OutOfMemory"
        Unsupported -> "Unsupported"
        _ -> "Unrecognized"
