package samal.lang;

import samal.lang.Pipeline;

class Main {
  static function main() {
    final code = "
    module A.B.Main
    
    fn add(a : int, b : int) -> int {
      a + b
    }
    
    fn fib(n : int) -> int {
      if n < 2 {
        n
      } else {
        fib(n - 1) + fib(n - 2)
      }
    }
    
    fn reverseHelper<T>(la : [T], lb : [T]) -> [T] {
      match la {
        [head + tail] -> {
          @tail_call_self(tail, head + lb)
        }
        [] -> {
          lb
        }
      }
    }
    
    fn reverse<T>(l : [T]) -> [T] {
      reverseHelper<T>(l, [:T])
    }
    
    fn sum<T>(l : [T]) -> T {
      self = sum<T>
      match l {
        [] -> {
          0
        }
        [head + tail] -> {
          head + self(tail)
        }
      }
    }
    
    fn seq(n : int) -> [int] {
      if n < 1 {
        [n]
      } else {
        n + seq(n - 1)
      }
    }
    
    fn mainTwo() -> int {
      a = seq
      list = a(10000)
      sum<int>(reverse<int>(sum<int>(list) + list))
    }
    
    fn map<S, T>(l : [S], callback : fn(S) -> T) -> [T] {
      match l {
        [] -> [:T]
        [head + tail] -> callback(head) + map<S, T>(tail, callback)
      }
    }

    struct Sample {
      l : [int]
      m : [int]
    }
    struct SampleCollector {
      samples : [Sample]
    }
    
    fn mainThree() -> int {
      a = {
        outer = 1
        fn(param : int) -> int {
          inner = 5
          outer + param + inner
        }
      }
      a(10)
    }

    fn createSample(salt : int) -> Sample {
      a = seq(salt)
      b = map<int, int>(seq(salt), fn(n : int) -> int {
        n + 1
      })
      Sample{l : a, m : b}
    }

    fn createSamples() -> SampleCollector {
      samples = map<int, Sample>(seq(200), fn(i : int) -> Sample {
        createSample(i)
      })
      SampleCollector{samples : samples}
    }
    
    struct Point<T> {
      x : T
      y : T
    }
    fn main() -> Point<int> {
      Point<int>{y : 5, x : 10}
    }";
    var pipeline = new Pipeline(TargetType.CppFiles("out", "gcc"));
    pipeline.add("Main", code);
    var files = pipeline.generate("A.B.Main.main");
    #if js
    js.Lib.eval(files[0].content);
    #end
  }
}

