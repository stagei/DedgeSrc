using DedgeCommon;
// See https://aka.ms/new-console-template for more information
DedgeNLog.Info("Starting TestNoNameSpace");
Console.WriteLine("Hello, World!");
DedgeNLog.EnableDatabaseLogging(new DedgeConnection.ConnectionKey(DedgeConnection.FkApplication.FKM,DedgeConnection.FkEnvironment.DEV));
string test = GlobalFunctions.GetNamespaceClassMethodName();
DedgeNLog.StartOperation("TestNoNameSpace1",2);
DedgeNLog.StartOperation("TestNoNameSpace2",3);
DedgeNLog.OperationProgression();
DedgeNLog.OperationProgression();
DedgeNLog.OperationProgression();
DedgeNLog.OperationProgression();
DedgeNLog.OperationProgression();
DedgeNLog.OperationProgression();
DedgeNLog.OperationProgression();
DedgeNLog.OperationProgression();
DedgeNLog.OperationProgression();
DedgeNLog.EndOperation();
DedgeNLog.OperationProgression();

Console.WriteLine(test);
