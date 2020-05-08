function [u,A,asst,solt] = PoissonVEM(node,elem,pde)
%% POISSONVEM solve Poisson equation using virtual element method
%
%     -\Delta u = f,
%             u = g_D on the Dirichelet boundary edges
% in a domain described by node and elem, with boundary edges Dirichlet.
% Each element could be different polygon shape.
%
% Input:
%   node, elem: standard mesh data;
%   pde.f: functional handle right side or data
%   pde.g_D: functional handle for Dirichelet condition
%
% Output:
%   u: solution on the current mesh
%   A: stiffness matrix
%
% Example
%
%     node = [0,0; 0,0.5; 0,1; 0.5,0;1,0;0.5,0.5;0.5,1;1,0.5,1,1];
%     elem = [1,4,6,2; 6,8,9,7;4,5,8,6;2,6,7,3];
%     pde.f = inline('ones(size(p),1)','p');
%     pde.exactu = inline('(-p(:,1).^2-p(:,2).^2)/4','p');
%     [u,A] = PoissonVEM(node,elem,pde);
%     uI = pde.exactu(node);
%     error = sqrt((u-uI)'*A*(u-uI));
%
% See also Poisson, PoissonS
%
% The code is based on the following reference but optimized using
% vectorization to avoid for loops.
%
% Reference:
%
% Reference:  'The Hitchhiker's guide to the virtual element method'.
% by L.Beirao da Veiga, F.Brezzi, L.D.marini, A.Russo.2013


%% Assemble the matrix equation
N = size(node,1); % The number of nodes
elemVertexNumber = cellfun('length',elem);% the number of vertices per element
nnz = sum(elemVertexNumber.^2);
ii = zeros(nnz,1); %initialization
jj = zeros(nnz,1);
ss = zeros(nnz,1);
b = zeros(N,1);
edge = zeros(sum(elemVertexNumber),2);
index = 0;
edgeIdx = 1;
tic;
for Nv = min(elemVertexNumber):max(elemVertexNumber)
    % find polygons with Nv vertices
    idx = find(elemVertexNumber == Nv); % index of elements with Nv vertices
    NT = length(idx); % the number of elements having the same number of vertices
    % vertex index and coordinates
    vertex = cell2mat(elem(idx));
    x1 = reshape(node(vertex,1),NT,Nv);
    y1 = reshape(node(vertex,2),NT,Nv);
    x2 = circshift(x1,[0,-1]);
    y2 = circshift(y1,[0,-1]);
    % record edges
    nextIdx = edgeIdx + NT*Nv;
    newEdgeIdx = edgeIdx:nextIdx-1;
    edge(newEdgeIdx,1) = vertex(:); % get edge per element
    vertexShift = circshift(vertex,[0,-1]);
    edge(newEdgeIdx,2) = vertexShift(:);
    edgeIdx = nextIdx;
    % Compute geometry quantity: edge, normal, area, center
    bdIntegral = x1.*y2 - y1.*x2;
    area = sum(bdIntegral,2)/2; % the area per element
    h = repmat(sqrt(abs(area)),1,Nv); % h = sqrt(area) not the diameter
    cx = sum((x1+x2).*bdIntegral,2)./(6*area); % the first part of the centroid
    cy = sum((y1+y2).*bdIntegral,2)./(6*area); % the second part of the centroid
    normVecx = y2 - y1; % normal vector is a rotation of edge vector
    normVecy = x1 - x2;
    % matrix B, D, I - P
    Bx = (normVecx + circshift(normVecx,[0,1]))./(2*h); % average of normal vectors
    By = (normVecy + circshift(normVecy,[0,1]))./(2*h); % in adjaency edges
    Dx = (x1 - repmat(cx,1,Nv))./h; %  m(x) = (x - cx)/h
    Dy = (y1 - repmat(cy,1,Nv))./h;
    c1 = (1 - (repmat(sum(Dx,2),1,Nv).*Bx + repmat(sum(Dy,2),1,Nv).*By))/Nv;
    IminusP = zeros(NT,Nv,Nv);
    for i = 1:Nv
        for j = 1:Nv
            IminusP(:,i,j) = - c1(:,j) - Dx(:,i).*Bx(:,j) - Dy(:,i).*By(:,j);
        end
        IminusP(:,i,i) = ones(NT,1) + IminusP(:,i,i);
    end
    % assemble the matrix
    for i = 1:Nv
        for j = 1:Nv
            ii(index+1:index+NT) = vertex(:,i);
            jj(index+1:index+NT) = vertex(:,j);
            ss(index+1:index+NT) = Bx(:,i).*Bx(:,j) + By(:,i).*By(:,j) ...
                + dot(IminusP(:,:,i),IminusP(:,:,j),2);
            index = index + NT;
        end
    end
    % compute the right hand side
    ft =  area.*pde.f([cx cy])/Nv;
    b = b + accumarray(vertex(:),repmat(ft,Nv,1),[N,1]);
end
A = sparse(ii,jj,ss,N,N);
asst = toc;
%% Find boundary edges and nodes
totalEdge = sort(edge(:,1:2),2);
[i,j,s] = find(sparse(totalEdge(:,2),totalEdge(:,1),1));
bdEdge  = [j(s==1), i(s==1)]; % find the boundary edge
isBdNode = false(N,1);
isBdNode(bdEdge) = true;
bdNode = find(isBdNode);    % get the boundary node

%% Impose boundary conditions
u = zeros(N,1);
u(bdNode) = pde.g_D(node(bdNode,:));
b = b - A*u;

%% Solve Au = b
freeNode = find(~isBdNode); % get the interior node
tic;
u(freeNode) = A(freeNode,freeNode)\b(freeNode);
solt = toc;