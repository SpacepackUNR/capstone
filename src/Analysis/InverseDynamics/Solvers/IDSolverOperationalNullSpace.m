% Solves the inverse dynamics using an operational null space approach. The
% objective function is a classic gradient descent (the matrix W0).
%
% Author        : Darwin LAU
% Created       : 2015
% Description   : The formulation of this ID is analogous to that of the
%       operational space kinematics. Assume that 
%       w = Af (w - wrench, f - cable force); then
%       f = A^# w + N(A) f_0; where
%       f_0 = - W0 d(w(f))/df and w is some objective function we wish to
%       minimise
%       
%       In the modified solution, the f_0 term is modified to ensure the
%       cable force and other constraints are satisfied.
classdef IDSolverOperationalNullSpace < IDSolverBase
    
    properties (SetAccess = private)
        W0
        qp_solver_type
        objective
        constraints = {}
        options
        f0_previous = []
    end
    methods
        % A constructor for the class.
        function id = IDSolverOperationalNullSpace(model,objective, qp_solver_type, W0)
            id@IDSolverBase(model);
            id.objective = objective;
            id.qp_solver_type = qp_solver_type;
            id.W0 = W0;
            id.active_set = [];
            id.options = [];
        end
        
        % The implementation of the resolveFunction
        function [cable_forces,Q_opt, id_exit_type] = resolveFunction(obj, dynamics)            
            % Form the linear EoM constraint
            % M\ddot{q} + C + G + F_{ext} = -J^T f (constraint)
            [A_eom, b_eom] = IDSolverBase.GetEoMConstraints(dynamics);  
            % Form the lower and upper bound force constraints
            fmin = dynamics.forcesMin;
            fmax = dynamics.forcesMax;
            
            % Get objective function
            obj.objective.updateObjective(dynamics);
            if (~isempty(obj.f_previous))
                [~, grad_f] = obj.objective.evaluateFunction(obj.f_previous);
            else
                grad_f = zeros(dynamics.numCables,1);
            end
            
            f0_nom = - obj.W0 * grad_f;
            A_pinv = A_eom'/(A_eom * A_eom');
            A_null = eye(dynamics.numCables) - A_pinv * A_eom;
            f_task = A_pinv * b_eom;
            
            QP_A = 2 * eye(dynamics.numCables);
            QP_b = -2 * f0_nom;
                    
            A_ineq = [-A_null; A_null];
            b_ineq = [-(fmin - f_task); (fmax - f_task)];
            
            for i = 1:length(obj.constraints)
                obj.constraints{i}.updateConstraint(dynamics);
                A_ineq = [A_ineq; obj.constraints{i}.A * A_null];
                b_ineq = [b_ineq; obj.constraints{i}.b - obj.constraints{i}.A * f_task];                
            end

            switch (obj.qp_solver_type)
                case ID_QP_SolverType.MATLAB
                    if(isempty(obj.options))
                        obj.options = optimoptions('quadprog', 'Display', 'off', 'MaxIter', 100);
                    end 
                    [f0_soln, id_exit_type] = id_qp_matlab(QP_A, QP_b, A_ineq, b_ineq, [], [], [], [], obj.f0_previous, obj.options);
               case ID_QP_SolverType.OPTITOOLBOX_IPOPT
                    [f0_soln, id_exit_type] = id_qp_optitoolbox_ipopt(QP_A, QP_b, A_ineq, b_ineq, [], [], [], [], obj.f0_previous);
                case ID_QP_SolverType.OPTITOOLBOX_OOQP
                    [f0_soln, id_exit_type] = id_qp_optitoolbox_ooqp(QP_A, QP_b, A_ineq, b_ineq, [], [], [], [], obj.f0_previous);
                otherwise
                    error('ID_QP_SolverType type is not defined');
            end
            
            if (id_exit_type ~= IDSolverExitType.NO_ERROR)
                cable_forces = dynamics.cableModel.FORCES_INVALID;
                Q_opt = inf;
            else
                cable_forces = f_task + A_null * f0_soln;
                Q_opt = obj.objective.evaluateFunction(cable_forces);
            end            
            obj.f0_previous = f0_soln;
            obj.f_previous = cable_forces;
        end
    end
    
end

