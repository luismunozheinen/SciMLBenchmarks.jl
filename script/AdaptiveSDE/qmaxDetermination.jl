
using Distributed
addprocs()

@everywhere qs = 1.0 + 2.0.^(-5:2)
times = Array{Float64}(undef,length(qs),4)
means = Array{Float64}(undef,length(qs),4)

@everywhere begin
  using StochasticDiffEq, DiffEqBase, DiffEqProblemLibrary, Random,
        Plots, ParallelDataTransfer, DiffEqMonteCarlo
  Random.seed!(99 + myid())
  full_prob = oval2ModelExample(largeFluctuations=true,useBigs=false)
  prob = remake(full_prob,tspan=(0.0,1.0))
  println("Solve once to compile.")
  sol = solve(prob,EM(),dt=1/2^(18))
  Int(sol.u[end][1]!=NaN)
  println("Compilation complete.")
  num_runs = 10000

  probs = Vector{SDEProblem}(undef,3)
  p1 = Vector{Any}(undef,3)
  p2 = Vector{Any}(undef,3)
  p3 = Vector{Any}(undef,3)
  ## Problem 1
  probs[1] = prob_sde_linear
  ## Problem 2
  probs[2] = prob_sde_wave
  ## Problem 3
  probs[3] = prob_sde_additive
end
println("Setup Complete")

## Timing Runs

@everywhere function runAdaptive(i,k)
  sol = solve(prob,SRIW1(),dt=1/2^(8),abstol=2.0^(-15),reltol=2.0^(-10),maxIters=Int(1e12),qmax=qs[k])
  Int(any(isnan,sol[end]) || sol.t[end] != 1)
end

#Compile
monte_prob = MonteCarloProblem(probs[1])
test_mc = solve(monte_prob,SRIW1(),dt=1/2^(4),adaptive=true,num_monte=1000,abstol=2.0^(-1),reltol=0)
calculate_monte_errors(test_mc);


for k in eachindex(qs)
  ParallelDataTransfer.sendto(workers(), k=k)
  @everywhere Random.seed!(99 + myid())
  adaptiveTime = @elapsed numFails = sum(pmap((i)->runAdaptive(i,k),1:num_runs))
  println("k was $k. The number of Adaptive Fails is $numFails. Elapsed time was $adaptiveTime")
  times[k,4] = adaptiveTime
end


for k in eachindex(probs)
  println("Problem $k")
  ## Setup
  prob = probs[k]
  ParallelDataTransfer.sendto(workers(), prob=prob)

  for i in eachindex(qs)
    ParallelDataTransfer.sendto(workers(), i=i)
    msim = solve(monte_prob,dt=1/2^(4),SRIW1(),adaptive=true,num_monte=num_runs,abstol=2.0^(-13),reltol=0,qmax=qs[i])
    test_msim = calculate_monte_errors(msim)
    times[i,k] = test_msim.elapsedTime
    means[i,k] = test_msim.error_means[:final]
    println("for k=$k and i=$i, we get that the error was $(means[i,k]) and it took $(times[i,k]) seconds")
  end
end


using DiffEqBenchmarks
DiffEqBenchmarks.bench_footer(WEAVE_ARGS[:folder],WEAVE_ARGS[:file])

