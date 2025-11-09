
## install

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
