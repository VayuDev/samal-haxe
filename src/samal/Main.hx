package samal;

import samal.Pipeline;

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

    struct Point {
      x : int
      y : int
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
    
    fn main() -> Point {
      p = Point{y:5, x:10}
    }";
    var pipeline = new Pipeline(TargetType.JSSingleFile("out/out.js"));
    pipeline.add("Main", code);
    var files = pipeline.generate("A.B.Main.main");
    #if js
    js.Lib.eval(files[0].content);
    #end
  }
}

