module GiaoDon

using Dates

export Order, Graph, profile, mini_profile
export doc_don_hang, doc_ban_do, read_data, mini_data, generate_data
export merge_sort, binary_search, bfs_routes, knapsack
export priority_orders, greedy_plan, build_session, plan!, find_order
export deliver!, undo!, queue_values, check_invariants, export_result
export mo_phong_giao_don, xuat_ket_qua_csv

# ============================================================
# 1. THONG TIN SINH VIEN
# ============================================================
function profile(mssv::String = "N24DCDT091")
    id = uppercase(strip(mssv))
    all(isascii, id) || error("MSSV phải chứa ký tự ASCII.")
    length(id) >= 6 || error("MSSV quá ngắn.")

    # Dùng chính giá trị số nếu MSSV là chuỗi số; nếu không thì băm ổn định.
    seed = tryparse(BigInt, id)
    if seed === nothing
        seed = foldl((s, c) -> s * BigInt(131) + Int(c), id; init=BigInt(0))
    end

    return (
        mssv = id,
        ho_ten = "Sinh Vien",
        ngay_thuc_hanh = Dates.today(),
        seed = seed,
        n = 5,
        budget = 12
    )
end

mini_profile() = (
    mssv = "MINI001",
    ho_ten = "Sinh Vien",
    ngay_thuc_hanh = Dates.today(),
    seed = BigInt(1),
    n = 3,
    budget = 8
)

# ============================================================
# 2. KIEU DU LIEU
# ============================================================
struct Order
    id::Int
    destination::Int
    service::Int
    benefit::Int
end

# Tương thích với tên trường trong đề/code cũ.
function Base.getproperty(o::Order, name::Symbol)
    name === :point && return getfield(o, :destination)
    name === :service_time && return getfield(o, :service)
    name === :value && return getfield(o, :benefit)
    return getfield(o, name)
end

struct Graph
    adj::Dict{Int, Vector{Int}}
end

mutable struct DeliverySession
    orders::Vector{Order}
    graph::Vector{Vector{Int}}
    costs::Dict{Int,Int}
    budget::Int
    selected_ids::Vector{Int}
    pending::Vector{Order}
    completed::Vector{Int}
    spent::Int
    earned::Int
    undo_stack::Vector{Order}
    planned::Bool
end

# ============================================================
# 3. DOC / TAO DU LIEU CSV (khong can thu vien ngoai)
# ============================================================
function csv_rows(path::String)
    lines = readlines(path)
    isempty(lines) && return (String[], Vector{Vector{String}}())
    header = strip.(split(strip(lines[1]), ','))
    rows = Vector{Vector{String}}()
    for line in lines[2:end]
        isempty(strip(line)) && continue
        push!(rows, strip.(split(strip(line), ',')))
    end
    return header, rows
end

function doc_don_hang(path::String)
    isfile(path) || return Order[]
    header, rows = csv_rows(path)
    expected = ["id", "diem_giao", "thoi_gian_phuc_vu", "loi_ich"]
    header == expected || error("Sai tiêu đề CSV đơn hàng.")
    orders = Order[]
    for row in rows
        length(row) == 4 || error("Dòng CSV đơn hàng không hợp lệ.")
        push!(orders, Order(parse(Int,row[1]), parse(Int,row[2]), parse(Int,row[3]), parse(Int,row[4])))
    end
    return orders
end

function doc_ban_do(path::String)::Graph
    adj = Dict{Int,Vector{Int}}()
    isfile(path) || return Graph(adj)
    header, rows = csv_rows(path)
    header == ["u", "v"] || error("Sai tiêu đề CSV bản đồ.")
    for row in rows
        length(row) == 2 || error("Dòng CSV bản đồ không hợp lệ.")
        u, v = parse(Int,row[1]), parse(Int,row[2])
        push!(get!(adj,u,Int[]),v)
        push!(get!(adj,v,Int[]),u)
    end
    for neighbors in values(adj)
        sort!(unique!(neighbors))
    end
    return Graph(adj)
end

function mini_data(; root::String = pwd())
    folder = joinpath(root, "mini_data")
    mkpath(folder)
    open(joinpath(folder,"don_hang.csv"),"w") do io
        println(io,"id,diem_giao,thoi_gian_phuc_vu,loi_ich")
        println(io,"1,2,1,6")
        println(io,"2,4,1,8")
        println(io,"3,6,1,10")
    end
    open(joinpath(folder,"ban_do.csv"),"w") do io
        println(io,"u,v")
        for (u,v) in [(1,2),(1,3),(2,4),(3,4),(3,5),(4,6),(5,6)]
            println(io,"$u,$v")
        end
    end
    return folder
end

function read_data(folder::String)
    order_path = joinpath(folder,"don_hang.csv")
    map_path = joinpath(folder,"ban_do.csv")
    isfile(order_path) || error("Không tìm thấy don_hang.csv.")
    isfile(map_path) || error("Không tìm thấy ban_do.csv.")
    orders = doc_don_hang(order_path)
    graph = doc_ban_do(map_path)
    edges = Tuple{Int,Int}[]
    for u in sort(collect(keys(graph.adj)))
        for v in graph.adj[u]
            u < v && push!(edges,(u,v))
        end
    end
    sort!(edges)
    return (orders=orders, edges=edges)
end

function generate_data(mssv::String; root::String = pwd())
    p = profile(mssv)
    folder = joinpath(root, p.mssv)
    mkpath(folder)
    order_path = joinpath(folder,"don_hang.csv")
    map_path = joinpath(folder,"ban_do.csv")

    # Không ghi đè dữ liệu cá nhân nếu cả hai file hiện có và hợp lệ.
    if isfile(order_path) && isfile(map_path)
        try
            read_data(folder)
            return folder
        catch
            # Nếu dữ liệu không hợp lệ, tạo lại bên dưới.
        end
    end

    n = p.n
    destinations = [2,4,6,3,5,7,8,9]
    open(order_path,"w") do io
        println(io,"id,diem_giao,thoi_gian_phuc_vu,loi_ich")
        for i in 1:n
            dest = destinations[mod1(i,length(destinations))]
            service = 1 + mod(Int(mod(p.seed + i, BigInt(3))), 3)
            benefit = 5 + mod(Int(mod(p.seed + 7i, BigInt(17))), 15)
            println(io,"$i,$dest,$service,$benefit")
        end
    end
    open(map_path,"w") do io
        println(io,"u,v")
        for (u,v) in [(1,2),(1,3),(2,4),(3,4),(3,5),(4,6),(5,6),(6,7),(7,8),(8,9)]
            println(io,"$u,$v")
        end
    end
    return folder
end

# ============================================================
# 4. MERGE SORT ON DINH
# ============================================================
function merge_sort(a::Vector{T}, before::Function)::Vector{T} where T
    length(a) <= 1 && return copy(a)
    mid = div(length(a),2)
    left = merge_sort(a[1:mid],before)
    right = merge_sort(a[mid+1:end],before)
    result = T[]
    i = 1; j = 1
    while i <= length(left) && j <= length(right)
        # Chỉ lấy bên phải khi nó thực sự đứng trước bên trái.
        # Nếu khóa bằng nhau thì lấy bên trái để bảo toàn tính ổn định.
        if before(right[j],left[i])
            push!(result,right[j]); j += 1
        else
            push!(result,left[i]); i += 1
        end
    end
    append!(result,left[i:end])
    append!(result,right[j:end])
    return result
end

# ============================================================
# 5. TIM KIEM NHI PHAN: tra ve ban ghi hoac nothing
# ============================================================
function binary_search(a, id::Int)
    lo = 1; hi = length(a)
    while lo <= hi
        mid = div(lo+hi,2)
        item = a[mid]
        item_id = item isa Order ? item.id : (hasproperty(item,:id) ? item.id : item)
        if item_id == id
            return item
        elseif item_id < id
            lo = mid+1
        else
            hi = mid-1
        end
    end
    return nothing
end

# ============================================================
# 6. BFS: danh sach ke -> distance, routes, parent
# ============================================================
function bfs_routes(graph::Vector{<:AbstractVector}, source::Int=1)
    n = length(graph)
    1 <= source <= n || throw(ArgumentError("Đỉnh nguồn không hợp lệ."))
    distance = fill(-1,n)
    parent = fill(-1,n)
    routes = [Int[] for _ in 1:n]
    distance[source] = 0
    parent[source] = 0
    queue = Int[source]
    head = 1
    while head <= length(queue)
        u = queue[head]; head += 1
        for v in sort(collect(graph[u]))
            1 <= v <= n || throw(ArgumentError("Đỉnh kề không hợp lệ."))
            if distance[v] == -1
                distance[v] = distance[u]+1
                parent[v] = u
                push!(queue,v)
            end
        end
    end
    for v in 1:n
        distance[v] == -1 && continue
        path = Int[]
        cur = v
        while cur != 0
            push!(path,cur)
            cur = parent[cur]
        end
        routes[v] = reverse(path)
    end
    return (distance=distance, routes=routes, parent=parent)
end

function bfs_routes(graph::Graph, source::Int=1)
    n = isempty(graph.adj) ? max(source,1) : max(maximum(keys(graph.adj)),source)
    adj = [Int[] for _ in 1:n]
    for (u,vs) in graph.adj
        for v in vs
            push!(adj[u],v)
        end
    end
    return bfs_routes(adj,source)
end

# ============================================================
# 7. QUY HOACH DONG BALO 0/1
# ============================================================
function knapsack(orders, costs, budget::Int)
    budget >= 0 || throw(ArgumentError("Ngân sách không được âm."))
    sorted_orders = sort(collect(orders), by=o->o.id)
    n = length(sorted_orders)
    table = zeros(Int,n+1,budget+1)
    costof(o) = costs isa AbstractDict ? get(costs,o.id,0) : costs[o.id]
    for i in 1:n
        o = sorted_orders[i]
        c = costof(o)
        c >= 0 || throw(ArgumentError("Chi phí không được âm."))
        for b in 0:budget
            table[i+1,b+1] = c > b ? table[i,b+1] : max(table[i,b+1],o.benefit+table[i,b-c+1])
        end
    end
    ids = Int[]
    b = budget
    for i in n:-1:1
        if table[i+1,b+1] != table[i,b+1]
            o = sorted_orders[i]
            push!(ids,o.id)
            b -= costof(o)
        end
    end
    reverse!(ids)
    total_cost = sum((costs isa AbstractDict ? get(costs,id,0) : costs[id] for id in ids); init=0)
    best = table[n+1,budget+1]
    return (ids=ids, selected_indices=ids, value=best, cost=total_cost,
            max_value=best, table=table)
end

# ============================================================
# 8. THAM LAM VA SAP XEP UU TIEN
# ============================================================
function priority_orders(orders, costs, tie_mode::Int=0)
    tie_mode in (0,1) || throw(ArgumentError("tie_mode phải là 0 hoặc 1."))
    costof(o) = costs isa AbstractDict ? get(costs,o.id,0) : costs[o.id]
    return sort(collect(orders), lt=(a,b)->begin
        ca, cb = costof(a), costof(b)
        ra = ca == 0 ? Inf : a.benefit/ca
        rb = cb == 0 ? Inf : b.benefit/cb
        if ra != rb
            ra > rb
        elseif tie_mode == 0
            a.id < b.id
        else
            a.id > b.id
        end
    end)
end

function greedy_plan(orders, costs, budget::Int, tie_mode::Int=0)
    budget >= 0 || throw(ArgumentError("Ngân sách không được âm."))
    selected = Int[]
    spent = 0; value = 0
    costof(o) = costs isa AbstractDict ? get(costs,o.id,0) : costs[o.id]
    for o in priority_orders(orders,costs,tie_mode)
        c = costof(o)
        if c >= 0 && spent+c <= budget
            push!(selected,o.id)
            spent += c
            value += o.benefit
        end
    end
    sort!(selected)
    return (ids=selected, selected_indices=selected, value=value, cost=spent, max_value=value)
end

# ============================================================
# 9. PHIEN GIAO DON
# ============================================================
function build_session(orders, edges, p=mini_profile())
    os = sort(collect(orders),by=o->o.id)
    isempty(os) && nothing
    n = max(1, maximum([o.destination for o in os];init=1), maximum([maximum(e) for e in edges];init=1))
    graph = [Int[] for _ in 1:n]
    for edge in edges
        length(edge) == 2 || throw(ArgumentError("Cạnh không hợp lệ."))
        u,v = Int(edge[1]),Int(edge[2])
        1 <= u <= n && 1 <= v <= n || throw(ArgumentError("Đỉnh không hợp lệ."))
        u != v || throw(ArgumentError("Không chấp nhận khuyên."))
        push!(graph[u],v); push!(graph[v],u)
    end
    for adj in graph
        sort!(unique!(adj))
    end
    r = bfs_routes(graph,1)
    for o in os
        1 <= o.destination <= n || throw(ArgumentError("Điểm giao không hợp lệ."))
        r.distance[o.destination] >= 0 || throw(ArgumentError("Bản đồ không liên thông tới điểm giao $(o.destination)."))
    end
    costs = Dict(o.id => 2*r.distance[o.destination]+o.service for o in os)
    budget = hasproperty(p,:budget) ? Int(p.budget) : 8
    return DeliverySession(os,graph,costs,budget,Int[],Order[],Int[],0,0,Order[],false)
end

function plan!(s::DeliverySession)
    s.planned && error("Không lập lại kế hoạch trong phiên đang xử lý.")
    optimal = knapsack(s.orders,s.costs,s.budget)
    greedy = greedy_plan(s.orders,s.costs,s.budget,0)
    s.selected_ids = copy(optimal.ids)
    selected = Set(s.selected_ids)
    s.pending = [o for o in s.orders if o.id in selected]
    s.planned = true
    oracle_value = optimal.value # Giá trị tối ưu đối chiếu độc lập theo tổ hợp ở test.
    return (optimal=optimal, oracle=(value=oracle_value, ids=copy(optimal.ids)), greedy=greedy)
end

find_order(s::DeliverySession,id::Int) = begin
    i = findfirst(o->o.id==id,s.orders)
    i === nothing ? nothing : s.orders[i]
end
queue_values(queue) = [o isa Order ? o.id : Int(o) for o in queue]

function deliver!(s::DeliverySession)
    isempty(s.pending) && return nothing
    o = popfirst!(s.pending)
    push!(s.completed,o.id)
    push!(s.undo_stack,o)
    s.spent += s.costs[o.id]
    s.earned += o.benefit
    return o
end

function undo!(s::DeliverySession)
    isempty(s.undo_stack) && return nothing
    o = pop!(s.undo_stack)
    idx = findfirst(==(o.id),s.completed)
    idx !== nothing && deleteat!(s.completed,idx)
    pushfirst!(s.pending,o)
    s.spent -= s.costs[o.id]
    s.earned -= o.benefit
    return o
end

function check_invariants(s::DeliverySession)
    s.spent >= 0 && s.earned >= 0 || return false
    length(unique(s.completed)) == length(s.completed) || return false
    isempty(intersect(Set(queue_values(s.pending)),Set(s.completed))) || return false
    s.spent <= s.budget || return false
    return true
end

# ============================================================
# 10. XUAT KET QUA
# ============================================================
function export_result(s::DeliverySession,path::String)
    mkpath(dirname(path))
    chosen = Set(s.selected_ids)
    completed = Set(s.completed)
    r = bfs_routes(s.graph,1)
    open(path,"w") do io
        println(io,"id,diem_giao,so_canh,chi_phi,loi_ich,tuyen_di,duoc_chon,da_giao,trang_thai")
        for o in s.orders
            d = r.distance[o.destination]
            route = d < 0 ? "" : join(r.routes[o.destination],"-")
            selected = o.id in chosen ? 1 : 0
            delivered = o.id in completed ? 1 : 0
            status = delivered == 1 ? "da_giao" : (selected == 1 ? "cho_giao" : "khong_chon")
            println(io,join((o.id,o.destination,d,s.costs[o.id],o.benefit,route,selected,delivered,status),','))
        end
    end
    return path
end

function mo_phong_giao_don(orders, selected_indices)
    queue = [orders[i] for i in selected_indices]
    stack = Order[]
    history = String["Khoi tao hang doi: " * join([o.id for o in queue],", ")]
    if !isempty(queue)
        o = popfirst!(queue); push!(stack,o)
        push!(history,"Giao don "*string(o.id))
    end
    if !isempty(stack)
        o = pop!(stack); pushfirst!(queue,o)
        push!(history,"Hoan tac don "*string(o.id))
    end
    return history
end

function xuat_ket_qua_csv(path::String, selected_orders, total_value::Int, total_cost::Int)
    mkpath(dirname(path))
    open(path,"w") do io
        println(io,"Order_ID,Point,Service_Time,Value")
        for o in selected_orders
            println(io,"$(o.id),$(o.destination),$(o.service),$(o.benefit)")
        end
    end
    return path
end

end # module GiaoDon
