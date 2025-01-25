import (
	"math"
)

type ExampleStruct struct {
	Value float64
}

func (e ExampleStruct) Compute() float64 {
	return math.Sqrt(e.Value)
}

