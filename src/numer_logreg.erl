-module(numer_logreg).

-include("numer.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([readfile/2,
         cost/3,
         gradient_descent/3,
         learn/6,
         cost/6,
         gradient_descent/9,
       %  learn_with_cost/9,
         learn_buf/11]).

bin_to_num(Elem) ->
    try list_to_float(Elem)
    	catch error:badarg -> list_to_integer(Elem)
    end.

readfile(FileName, EOL) ->
    {ok, Binary} = file:read_file(FileName),
    Lines = string:tokens(erlang:binary_to_list(Binary), EOL),
    [[bin_to_num(X) || X<-string:tokens(Y, ",")] || Y<-Lines].

cost(Theta, X, Y) ->
    %H = sigmoid(gemm(1*Theta*X + 0*H))
    %J = -1/m * (Y * log(H) + (1-Y) * log(1-H)) 
    _m = length(Y),

    % ?debugMsg(io_lib:format("~n Theta m,k: ~p ~p",[_m,_k])),
    % ?debugMsg(io_lib:format("~n X m,n: ~p ~p",[length(X),length(hd(X))])),

    % tmp1 = gemm(1*Theta*X + 0*H)
    Tmp1 = numer_helpers:gemm(no_transpose, transpose, 1.0, [Theta], X,   0.0, []),


    % H=sigmoid(Theta*X)
    H = numer_helpers:sigmoid(Tmp1),


    %Tmp2 = log(H)
    Tmp2 =  numer_helpers:log(H),

    % tmp3 = (1 - Y)
    % using saxpy:  y = ax + y
    % =>tmp3 = -1.0 * Y + 1    
    Tmp3 = numer_helpers:saxpy(-1.0, Y, numer_helpers:ones(length(Y))),

    % tmp4 = (1 - H)
    Tmp4 = numer_helpers:saxpy(-1.0, H, numer_helpers:ones(length(H))),

    %Tmp5 = log(1 - H)
    Tmp5 = numer_helpers:log(Tmp4),

    %    J = (1/m)*(-y * log(h) - (1 - y) * log(1 - h));
    %or: J = -1/m * ( (Y*Tmp2) + Tmp3*Tmp5)
    %Using gemv: y <- α op ( A ) x + β y
    % gemv(-1/m, Y, Tmp2, -1/m, gemv(1,Tmp3,Tmp5, 0, []))

    Tmp6 = numer_helpers:gemv(no_transpose, 1.0, Tmp3, Tmp5, 0.0, []), 
    J = numer_helpers:gemv(no_transpose, -1.0/_m, Y, Tmp2, -1.0/_m, Tmp6),
    [element(1,string:to_float(hd(io_lib:format("~.6f",[hd(J)]))))].

gradient_descent(Theta, X, Y) -> 
    %Gradient descent:
    %Delta = X'*(sigmoid(X*theta)-y);
    %theta = theta - (alpha*1/m)*Delta;

    % tmp1 = gemm(1*Theta*X + 0*H)
    Tmp1 = numer_helpers:gemm(no_transpose, transpose, 1.0, [Theta], X, 0.0, []),


    % H=sigmoid(Theta*X)
    H = numer_helpers:sigmoid(Tmp1),

    %H - Y
    Tmp3 = numer_helpers:saxpy(-1.0, Y, H),

    _m = length(Y),
    %gemv: y <- α op ( A ) x + β y
    Grad = numer_helpers:gemm(no_transpose, no_transpose, 1.0/_m, [Tmp3], X, 0.0, []).

learn(Theta, X, Y, Alpha, Iterations, []) ->
    %theta = theta - alpha*Grad; => saxpy:  y = ax + y
    Theta_tmp = numer_helpers:saxpy(-Alpha, gradient_descent(Theta, X, Y), Theta), 
    learn(Theta_tmp, X, Y, Alpha, Iterations-1 , cost(Theta_tmp, X, Y));
learn(Theta, X, Y, Alpha, 0, J_hist) ->
    Theta_tmp = numer_helpers:saxpy(-Alpha, gradient_descent(Theta, X, Y), Theta),
    [Theta_tmp, J_hist];
learn(Theta, X, Y, Alpha, Iterations, J_hist) ->
    Theta_tmp = numer_helpers:saxpy(-Alpha, gradient_descent(Theta, X, Y), Theta),
    learn(Theta_tmp, X, Y, Alpha, Iterations-1 , J_hist ++ cost(Theta_tmp, X, Y)).



cost(Ctx, Theta, X, Y, _num_features, _num_samples) ->
    
    %H = sigmoid(gemm(1*Theta*X + 0*H))
    %J = -1/m * (Y * log(H) + (1-Y) * log(1-H)) 
    _m = _num_samples,
    _n = _num_features,
    _k = _num_samples,

    % tmp1 = gemm(1*Theta*X + 0*H)
    {ok, Tmp1} = numer_buffer:zeros(matrix, float, row_major, 1, _m),
    ok = numer_blas:gemm(Ctx, no_transpose, transpose,  1, _m, _num_features, 1.0, Theta, X, 0.0, Tmp1),

    % H=sigmoid(Theta*X)
    {ok, H} = numer_buffer:new(matrix, float, row_major, 1, _m),
    ok = numer_kernels:sigmoid(Ctx, Tmp1, H),


    %Tmp2 = log(H)
    %Tmp2 =  numer_helpers:log(H),
    {ok, Tmp2} = numer_buffer:new(matrix, float, row_major, 1, _m),
    ok = numer_kernels:log(Ctx, H, Tmp2),

    % tmp3 = (1 - Y)
    % using saxpy:  y = ax + y
    % =>tmp3 = -1.0 * Y + 1    
    {ok, Tmp3} = numer_buffer:ones(matrix, float, row_major, 1, _m),
    ok = numer_blas:saxpy(Ctx, -1.0, Y, Tmp3),

    % tmp4 = (1 - H)
    {ok, Tmp4} = numer_buffer:ones(float,_m),
    ok = numer_blas:saxpy(Ctx, -1.0, H, Tmp4),

    %Tmp5 = log(1 - H)
    {ok, Tmp5} = numer_buffer:new(float,_m),
    ok = numer_kernels:log(Ctx, Tmp4, Tmp5),

    %    J = (1/m)*(-y * log(h) - (1 - y) * log(1 - h));
    %i.e.: J = -1/m * ( (Y*Tmp2) + Tmp3*Tmp5)
    %Using gemv: y <- α op ( A ) x + β y
    % gemv(-1/m, Y, Tmp2, -1/m, gemv(1,Tmp3,Tmp5, 0, []))

    %Tmp6 = numer_helpers:gemv(no_transpose, 1.0, Tmp3, Tmp5, 0.0, []), %!!!!!Tmp3 may need transpose
    {ok, Tmp6} = numer_buffer:new(float,_m),
    ok = numer_blas:gemv(Ctx, no_transpose, 1, _m, 1.0, Tmp3, Tmp5, 0.0, Tmp6),
    
    ok = numer_blas:gemv(Ctx, no_transpose, 1,_m,  -1.0/_m, Y, Tmp2, -1.0/_m, Tmp6),
    {ok, J} = numer_buffer:read(Tmp6),
    numer_buffer:destroy(Tmp6),
    numer_buffer:destroy(Tmp5),
    numer_buffer:destroy(Tmp4),
    numer_buffer:destroy(Tmp3),
    numer_buffer:destroy(Tmp2),
    numer_buffer:destroy(Tmp1),
    numer_buffer:destroy(H),    
    [element(1,string:to_float(hd(io_lib:format("~.6f",[hd(J)]))))].


 %Grad = (1/m)* ( X * (sigmoid(Theta*X) - Y) )
gradient_descent(Ctx, Theta, X, Y, _num_features, _m, Tmp1, H, Grad) -> 
    ok = numer_blas:gemm(Ctx, no_transpose, transpose,  1, _m, _num_features, 1.0, Theta, X, 0.0, Tmp1),      % tmp1 = 1*Theta*X + 0*H
    ok = numer_kernels:sigmoid(Ctx, Tmp1, H),                                                                 % H=sigmoid(Theta*X)
    ok = numer_blas:saxpy(Ctx, -1.0, Y, H),                                                                   %H - Y
    ok = numer_blas:gemm(Ctx, no_transpose, no_transpose, 1, _num_features, _m,  1.0/_m, H, X, 0.0, Grad),    %gemv: y <- α op ( A ) x + β y
    Grad.

% learn_with_cost(Ctx, Theta, X, Y, Alpha, Iterations, _num_features, _m, []) ->
%     %theta = theta - alpha*Grad; => saxpy:  y = ax + y
%     numer_blas:saxpy(Ctx, -Alpha, gradient_descent(Ctx, Theta, X, Y, _num_features, _m, Tmp1, H, Grad), Theta),
%     learn_with_cost(Ctx, Theta, X, Y, Alpha, Iterations-1 , _num_features, _m, cost(Ctx, Theta, X, Y, _num_features, _m));
% learn_with_cost(Ctx, Theta, X, Y, Alpha, 0, _num_features, _m, J_hist) when is_list(J_hist), J_hist /= [] ->
%     numer_blas:saxpy(Ctx,-Alpha, gradient_descent(Ctx, Theta, X, Y, _num_features, _m, Tmp1, H, Grad), Theta),
%     [Theta, J_hist];
% learn_with_cost(Ctx, Theta, X, Y, Alpha, Iterations, _num_features, _m, J_hist) when is_list(J_hist), J_hist /= []->
%     numer_blas:saxpy(Ctx,-Alpha, gradient_descent(Ctx, Theta, X, Y, _num_features, _m, Tmp1, H, Grad), Theta),
%     learn_with_cost(Ctx, Theta, X, Y, Alpha, Iterations-1, _num_features, _m, J_hist ++ cost(Ctx, Theta, X, Y, _num_features, _m)).


learn_buf(Ctx, Theta, X, Y, Alpha, 0, _num_features, _m, Tmp1, H, Grad)  ->
    numer_blas:saxpy(Ctx,-Alpha, gradient_descent(Ctx, Theta, X, Y, _num_features, _m, Tmp1, H, Grad), Theta),
    Theta;
learn_buf(Ctx, Theta, X, Y, Alpha, Iterations, _num_features, _m, Tmp1, H, Grad) ->
    numer_blas:saxpy(Ctx, -Alpha, gradient_descent(Ctx, Theta, X, Y, _num_features, _m, Tmp1, H, Grad), Theta),
    learn_buf(Ctx, Theta, X, Y, Alpha, Iterations-1 , _num_features, _m, Tmp1, H, Grad).   

