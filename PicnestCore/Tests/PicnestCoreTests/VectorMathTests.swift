import Testing
@testable import PicnestCore

struct VectorMathTests {
    @Test func matmulGivesCosine() throws {
        let a = [VectorMath.normalize([1, 0]), VectorMath.normalize([1, 1])]
        let b = [VectorMath.normalize([1, 0]), VectorMath.normalize([0, 1]), VectorMath.normalize([1, 1])]
        let m = VectorMath.matmul(a, b)
        try #require(m.count >= 2)
        #expect(m.count == 2 && m[0].count == 3)
        #expect(abs(m[0][0] - 1) < 1e-5)
        #expect(abs(m[0][1]) < 1e-5)
        #expect(abs(m[0][2] - 0.70710678) < 1e-5)
        #expect(abs(m[1][0] - 0.70710678) < 1e-5)
        #expect(abs(m[1][2] - 1) < 1e-5)
    }

    @Test func matmulEmptyInputs() {
        #expect(VectorMath.matmul([], [[1, 0]]).isEmpty)
        #expect(VectorMath.matmul([[1, 0]], []) == [[]])
    }

    @Test func dotAndNormalize() throws {
        #expect(VectorMath.dot([1, 2, 3], [4, 5, 6]) == 32)
        let n = VectorMath.normalize([3, 4])
        try #require(n.count >= 2)
        #expect(abs(n[0] - 0.6) < 1e-6 && abs(n[1] - 0.8) < 1e-6)
        #expect(VectorMath.normalize([0, 0]) == [0, 0])
    }

    @Test func softmaxSumsToOneAndIncreases() throws {
        let s = VectorMath.softmax([1, 2, 3], temperature: 1)
        #expect(abs(s.reduce(0, +) - 1) < 1e-5)
        try #require(s.count >= 3)
        #expect(s[0] < s[1] && s[1] < s[2])
    }

    @Test func softmaxLowTemperatureIsSharp() throws {
        let s = VectorMath.softmax([0.20, 0.25, 0.30], temperature: 0.01)
        try #require(s.count >= 3)
        #expect(s[2] > 0.99)
    }
}
