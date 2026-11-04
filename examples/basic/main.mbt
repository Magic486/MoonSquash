///|
fn main raise {
  let bytes = @squash.build_image([
    {
      path: "/etc/message",
      mode: 420,
      content: Regular(b"Hello from MoonSquash\n"),
    },
    { path: "/message", mode: 420, content: Hardlink("/etc/message"), },
    { path: "/link", mode: 511, content: Symbolic(b"etc/message"), },
  ])
  let image = @squash.open_image(bytes)
  let report = image.verify()
  println(
    "\{report.entries} paths, \{report.inodes} unique inodes, \{report.fragments} fragment blocks",
  )
  let file = image.lookup("/message")
  let text = image.read_file(file)
  println(@utf8.decode_lossy(text))
}
