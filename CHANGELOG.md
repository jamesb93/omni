## 0.2.1

1) Introducing the `loop` construct:

    ```nim
    loop 4 i:
        print i
    ```

2) Better error printing for invalid `def` and `struct` builds.

## 0.2.0

1) Support for command-like calls. Just like `nim`, it works for one arguments only:

    ```nim
    a = Data 10
    a = Data(10) #equivalent
    ```

2) Support for `new` statement, both as `dotExpr` and command:

    ```nim
    a = new Data
    a = new Data 10
    a = new Data(10)
    a = Data.new()
    a = Data.new(10)
    ```

3) Explicit casting at variables declaration will keep the type:

    ```nim
    a = int(1) #Will be int, not float!
    ```

4) Variables and `Buffers` can now be declared from the `ins` statement:

    ```nim
    ins 2:
        buffer Buffer
        speed  {1, 0, 10}

    outs 1

    init:
        phase = 0.0

    sample:
        scaled_rate = buffer.samplerate / samplerate
        out1 = buffer[phase]
        phase += (speed * scaled_rate)
        phase = phase % buffer.len
    ```

5) Added `tuples` support:

    ```nim
    def giveMeATuple():
        a (int, int) = (1, 2) #OR a = (int(1), int(2))
        b = (1, 2, a) #(float, float, (int, int))
        return b     

    init:
        a = giveMeATuple()
        print a[0]; print a[1]
        print a[2][0]; print a[2][1]
    ```

6) Introducing `modules` via the `use` / `require` statements (they are equivalent, still deciding which name I like better):

    `One.omni:`

    ```nim
    struct Something:
        a

    def someFunc():
        return 0.7
    ```

    `Two.omni`

    ```nim
    struct Something:
        a

    def someFunc():
        return 0.3
    ```

    `Three.omni:`

    ```nim
    use One:
        Something as Something1
        someFunc as someFunc1

    use Two:
        Something as Something2
        someFunc as someFunc2

    init:
        one = Something1()
        two = Something2()

    sample:
        out1 = someFunc1() + someFunc2()
    ```

    For more complex examples, check the `NewModules` folder in `omni_lang`'s tests.

7) Better handling of variables' scope. `if / elif / else / for / while` have their own scope, but won't overwrite variables of encapsulating scopes.

    ```nim
    init:
        a = 0
        if in1 > 0:
            a = 2 #Gonna change declared a
            b = 0 #b belongs to this if statement
        else:
            a = 3 #Gonna change declared a
            b = 1 #b belongs to this else statement
    ```
