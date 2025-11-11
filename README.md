Originally this is just a helper to speed up manpage openning...

```sh
ln -sf $(realpath zig-out/bin/cmdcache) ~/.local/bin/man
```

e.g. cache cmd result

before
```
$ hyperfine -w 5  'MANPAGER= man -l /usr/share/man/man1/gcc.1.gz'
Benchmark 1: MANPAGER= man -l /usr/share/man/man1/gcc.1.gz
  Time (mean ± σ):     439.6 ms ±  72.5 ms    [User: 730.6 ms, System: 30.8 ms]
  Range (min … max):   363.9 ms … 563.7 ms    10 runs
```

after
```
$ VIMRUNTIME=1 hyperfine -w 5 'MANPAGER= man -l /usr/share/man/man1/gcc.1.gz'
Benchmark 1: MANPAGER= man -l /usr/share/man/man1/gcc.1.gz
  Time (mean ± σ):     268.8 µs ± 692.2 µs    [User: 204.9 µs, System: 426.3 µs]
  Range (min … max):    28.8 µs … 5352.0 µs    3072 runs
```

## man is still slow
man is still slow for many other reasons, see [patches](./patches/)....
* we don't need slow check for platform compatibility: https://github.com/fish-shell/fish-shell/commit/1705bd14
* async `man.lua` if possible, and apply hl before set_lines
* `nvim +Man` is faster than use nvim as pager `nvim +Man!`
  * (since the later one pipe from man, never use `-l` in our pattern)

Another way is use terminal, but `gO` don't work well with
```sh
MANPAGER= nvim +'se scbk=1000000' +'term man gcc 2>/dev/null' +'se ft=man' +'exe "normal! \<c-n>\<c-\\>"'
```

how to patch
```lua
package.preload.man = function() return require('my.patch.man') end
```
